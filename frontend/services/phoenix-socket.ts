// services/phoenix-socket.ts
import { Socket, Channel } from 'phoenix';
import { useChatStore, useAuthStore } from '@/store/chat';
import { Message, UserStatus } from '@/types';
import toast from 'react-hot-toast';

type PresenceState = Record<string, { metas: Array<{ status: string; username: string }> }>;
type PresenceDiff  = { joins: PresenceState; leaves: PresenceState };

class PhoenixSocketService {
  private socket:      Socket | null = null;
  private channels:    Map<string, Channel> = new Map();
  private userChannel: Channel | null = null;
  private token:       string | null = null;

  // ── Connect / Disconnect ──────────────────────────────────────

  connect(token: string): Promise<void> {
    this.token = token;

    return new Promise((resolve, reject) => {
      const wsUrl = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:8080/socket';

      this.socket = new Socket(wsUrl, {
        params: { token },
        heartbeatIntervalMs: 30_000,
        reconnectAfterMs: (tries: number) => [1000, 2000, 5000, 10000][tries - 1] || 10000,
        logger: (kind: string, msg: string, data: unknown) => {
          if (process.env.NODE_ENV === 'development') {
            console.log(`[Phoenix ${kind}] ${msg}`, data);
          }
        },
      });

      this.socket.onOpen(() => {
        console.log('[Phoenix] Socket connected');
        this.joinUserChannel();
        resolve();
      });

      this.socket.onError((err) => {
        console.error('[Phoenix] Socket error:', err);
        reject(err);
      });

      this.socket.onClose(() => {
        console.log('[Phoenix] Socket closed');
      });

      this.socket.connect();
    });
  }

  disconnect() {
    this.channels.forEach((ch) => ch.leave());
    this.channels.clear();
    this.userChannel?.leave();
    this.userChannel = null;
    this.socket?.disconnect();
    this.socket = null;
    this.token = null;
  }

  get isConnected(): boolean {
    return this.socket?.isConnected() ?? false;
  }

  // ── User channel (presence, notifications) ────────────────────

  private joinUserChannel() {
    const userId = useAuthStore.getState().user?.id;
    if (!userId || !this.socket) return;

    this.userChannel = this.socket.channel(`user:${userId}`, {});

    this.userChannel
      .join()
      .receive('ok', () => console.log(`[Phoenix] Joined user:${userId}`))
      .receive('error', (err) => console.error('[Phoenix] User channel error:', err));

    this.userChannel.on('presence_state', (state: PresenceState) => {
      this.applyPresenceState(state);
    });
    this.userChannel.on('presence_diff', (diff: PresenceDiff) => {
      this.applyPresenceDiff(diff);
    });
  }

  // ── Room channels ─────────────────────────────────────────────

  joinRoom(roomId: string): Channel {
    if (this.channels.has(roomId)) {
      return this.channels.get(roomId)!;
    }

    if (!this.socket) throw new Error('Socket not connected');

    const channel = this.socket.channel(`room:${roomId}`, {});
    this.channels.set(roomId, channel);

    channel
      .join()
      .receive('ok', () => console.log(`[Phoenix] Joined room:${roomId}`))
      .receive('error', ({ reason }: { reason: string }) => {
        console.error(`[Phoenix] Failed to join room:${roomId}:`, reason);
        toast.error(`Could not join room: ${reason}`);
      })
      .receive('timeout', () => console.warn('[Phoenix] Join timed out, retrying…'));

    this.wireRoomEvents(channel, roomId);
    return channel;
  }

  leaveRoom(roomId: string) {
    const channel = this.channels.get(roomId);
    if (channel) {
      channel.leave();
      this.channels.delete(roomId);
    }
  }

  // ── Send events ───────────────────────────────────────────────

  sendMessage(roomId: string, content: string, threadId?: string): Promise<Message> {
    // BUG FIX: backend handle_in listens for "new_message" with key "content".
    // Was pushing "send_message" with key "content" — event name mismatch.
    return this.push(roomId, 'new_message', {
      content,
      thread_id: threadId ?? null,
      msg_type: 'text',
    });
  }

  sendTyping(roomId: string, isTyping: boolean) {
    // BUG FIX: backend handle_in("typing", ...) now accepts is_typing boolean.
    const channel = this.channels.get(roomId);
    channel?.push('typing', { is_typing: isTyping });
  }

  sendReadReceipt(roomId: string, messageId: string) {
    const channel = this.channels.get(roomId);
    channel?.push('read_receipt', { message_id: messageId });
  }

  loadMessages(roomId: string, before?: string): Promise<{ messages: Message[] }> {
    return this.push(roomId, 'load_messages', { before: before ?? null });
  }

  // ── Private helpers ───────────────────────────────────────────

  private push<T = unknown>(
    roomId: string,
    event: string,
    payload: Record<string, unknown>
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      const channel = this.channels.get(roomId);
      if (!channel) {
        reject(new Error(`Not joined room: ${roomId}`));
        return;
      }

      channel
        .push(event, payload)
        .receive('ok',     (resp: T) => resolve(resp))
        .receive('error',  (err: unknown) => reject(err))
        .receive('timeout', () => reject(new Error('Request timed out')));
    });
  }

  private wireRoomEvents(channel: Channel, roomId: string) {
    const store = useChatStore.getState();

    // New message broadcast
    channel.on('new_message', (msg: Message) => {
      store.addMessage(roomId, msg);
      const activeRoom  = useChatStore.getState().activeRoomId;
      const currentUser = useAuthStore.getState().user;
      if (msg.room_id !== activeRoom && msg.sender_id !== currentUser?.id) {
        toast(`New message in #${roomId.slice(0, 8)}`, { icon: '💬' });
      }
    });

    // BUG FIX: backend pushes "history" (not "message_history") in after_join.
    channel.on('history', ({ messages }: { messages: Message[] }) => {
      store.setMessages(roomId, messages);
    });

    // Edited message
    channel.on('message_edited', (msg: Message) => {
      store.updateMessage(roomId, msg.id, { content: msg.content, edited: true });
    });

    // Deleted message
    channel.on('message_deleted', ({ id }: { id: string }) => {
      store.deleteMessage(roomId, id);
    });

    // Reaction toggle
    channel.on('reaction_updated', ({
      message_id, reaction, user_id
    }: { message_id: string; reaction: string; user_id: string }) => {
      store.addReaction(roomId, message_id, reaction, user_id);
    });

    // BUG FIX: backend now sends separate "typing" / "stop_typing" events.
    // Listen for both and pass the correct boolean to setTyping.
    channel.on('typing', ({ user_id }: { user_id: string }) => {
      const currentUser = useAuthStore.getState().user;
      if (user_id !== currentUser?.id) {
        store.setTyping(roomId, user_id, true);
      }
    });

    channel.on('stop_typing', ({ user_id }: { user_id: string }) => {
      const currentUser = useAuthStore.getState().user;
      if (user_id !== currentUser?.id) {
        store.setTyping(roomId, user_id, false);
      }
    });

    // User joined/left
    channel.on('user_joined', ({ user_id }: { user_id: string }) => {
      console.log(`[Room ${roomId}] User joined: ${user_id}`);
    });
    channel.on('user_left', ({ user_id }: { user_id: string }) => {
      console.log(`[Room ${roomId}] User left: ${user_id}`);
    });

    // Kicked/banned
    channel.on('kicked', ({ reason }: { reason: string }) => {
      toast.error(`Removed from room: ${reason}`);
      store.setActiveRoom(null);
      this.leaveRoom(roomId);
    });

    // Room-level presence
    channel.on('presence_state', (state: PresenceState) => {
      this.applyPresenceState(state);
    });
    channel.on('presence_diff', (diff: PresenceDiff) => {
      this.applyPresenceDiff(diff);
    });
  }

  private applyPresenceState(state: PresenceState) {
    const { setUserStatus } = useChatStore.getState();
    Object.entries(state).forEach(([userId, { metas }]) => {
      const status = (metas[0]?.status ?? 'online') as UserStatus;
      setUserStatus(userId, status);
    });
  }

  private applyPresenceDiff({ joins, leaves }: PresenceDiff) {
    const { setUserStatus } = useChatStore.getState();
    Object.entries(joins).forEach(([userId, { metas }]) => {
      setUserStatus(userId, (metas[0]?.status ?? 'online') as UserStatus);
    });
    Object.entries(leaves).forEach(([userId]) => {
      setUserStatus(userId, 'offline');
    });
  }
}

// Singleton — one socket for the entire app lifetime
export const phoenixSocket = new PhoenixSocketService();

// BUG FIX: Sidebar, Login, and Register pages imported `wsService` from
// `@/services/websocket` (a file that does not exist). Export an alias so
// existing import paths resolve without touching every consumer file.
export const wsService = phoenixSocket;
