// store/chat.ts — Phoenix version
// Identical interface to v1; no store changes needed for Phoenix migration.
// The phoenix-socket service feeds events directly into these same actions.
import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import { Room, Message, Thread, User, UserStatus } from '@/types';

interface ChatStore {
  rooms:          Record<string, Room>;
  messages:       Record<string, Message[]>;
  activeRoomId:   string | null;
  activeThread:   Thread | null;
  typingUsers:    Record<string, Set<string>>;
  onlineUsers:    Record<string, UserStatus>;
  userCache:      Record<string, User>;
  sidebarOpen:    boolean;
  threadPanelOpen: boolean;

  setRooms:          (rooms: Room[]) => void;
  addRoom:           (room: Room) => void;
  updateRoom:        (roomId: string, updates: Partial<Room>) => void;
  setActiveRoom:     (roomId: string | null) => void;
  setMessages:       (roomId: string, messages: Message[]) => void;
  prependMessages:   (roomId: string, messages: Message[]) => void;
  addMessage:        (roomId: string, message: Message) => void;
  updateMessage:     (roomId: string, messageId: string, updates: Partial<Message>) => void;
  deleteMessage:     (roomId: string, messageId: string) => void;
  addReaction:       (roomId: string, messageId: string, emoji: string, userId: string) => void;
  setTyping:         (roomId: string, userId: string, isTyping: boolean) => void;
  setUserStatus:     (userId: string, status: UserStatus) => void;
  cacheUser:         (user: User) => void;
  setSidebarOpen:    (open: boolean) => void;
  setActiveThread:   (thread: Thread | null) => void;
  setThreadPanelOpen:(open: boolean) => void;
}

export const useChatStore = create<ChatStore>()(
  subscribeWithSelector((set) => ({
    rooms:           {},
    messages:        {},
    activeRoomId:    null,
    activeThread:    null,
    typingUsers:     {},
    onlineUsers:     {},
    userCache:       {},
    sidebarOpen:     true,
    threadPanelOpen: false,

    setRooms: (rooms) =>
      set({ rooms: Object.fromEntries(rooms.map((r) => [r.id, r])) }),

    addRoom: (room) =>
      set((s) => ({ rooms: { ...s.rooms, [room.id]: room } })),

    updateRoom: (roomId, updates) =>
      set((s) => ({
        rooms: { ...s.rooms, [roomId]: { ...s.rooms[roomId], ...updates } },
      })),

    setActiveRoom: (roomId) =>
      set({ activeRoomId: roomId, activeThread: null, threadPanelOpen: false }),

    setMessages: (roomId, messages) =>
      set((s) => ({ messages: { ...s.messages, [roomId]: messages } })),

    prependMessages: (roomId, messages) =>
      set((s) => ({
        messages: {
          ...s.messages,
          [roomId]: [...messages, ...(s.messages[roomId] || [])],
        },
      })),

    addMessage: (roomId, message) =>
      set((s) => {
        const existing = s.messages[roomId] || [];
        if (existing.some((m) => m.id === message.id)) return s;
        return {
          messages: { ...s.messages, [roomId]: [...existing, message] },
          rooms: s.rooms[roomId]
            ? { ...s.rooms, [roomId]: { ...s.rooms[roomId], last_message: message } }
            : s.rooms,
        };
      }),

    updateMessage: (roomId, messageId, updates) =>
      set((s) => ({
        messages: {
          ...s.messages,
          [roomId]: (s.messages[roomId] || []).map((m) =>
            m.id === messageId ? { ...m, ...updates } : m
          ),
        },
      })),

    deleteMessage: (roomId, messageId) =>
      set((s) => ({
        messages: {
          ...s.messages,
          [roomId]: (s.messages[roomId] || []).filter((m) => m.id !== messageId),
        },
      })),

    addReaction: (roomId, messageId, emoji, userId) =>
      set((s) => {
        const msgs = s.messages[roomId] || [];
        return {
          messages: {
            ...s.messages,
            [roomId]: msgs.map((m) => {
              if (m.id !== messageId) return m;
              const reactions = { ...(m.reactions || {}) };
              const users = reactions[emoji] || [];
              if (users.includes(userId)) {
                reactions[emoji] = users.filter((u) => u !== userId);
                if (!reactions[emoji].length) delete reactions[emoji];
              } else {
                reactions[emoji] = [...users, userId];
              }
              return { ...m, reactions };
            }),
          },
        };
      }),

    setTyping: (roomId, userId, isTyping) =>
      set((s) => {
        const room = new Set(s.typingUsers[roomId] || []);
        if (isTyping) room.add(userId);
        else room.delete(userId);
        return { typingUsers: { ...s.typingUsers, [roomId]: room } };
      }),

    setUserStatus: (userId, status) =>
      set((s) => ({ onlineUsers: { ...s.onlineUsers, [userId]: status } })),

    cacheUser: (user) =>
      set((s) => ({ userCache: { ...s.userCache, [user.id]: user } })),

    setSidebarOpen:    (open) => set({ sidebarOpen: open }),
    setActiveThread:   (thread) => set({ activeThread: thread, threadPanelOpen: thread !== null }),
    setThreadPanelOpen:(open) => set({ threadPanelOpen: open }),
  }))
);

// ── Auth store ────────────────────────────────────────────────

interface AuthStore {
  user:         User | null;
  accessToken:  string | null;
  refreshToken: string | null;
  isLoading:    boolean;

  setAuth:    (user: User, accessToken: string, refreshToken: string) => void;
  clearAuth:  () => void;
  setLoading: (loading: boolean) => void;
  setUser:    (user: User) => void;
}

export const useAuthStore = create<AuthStore>()((set) => ({
  user:         null,
  accessToken:  null,
  refreshToken: null,
  isLoading:    true,

  setAuth:    (user, accessToken, refreshToken) =>
    set({ user, accessToken, refreshToken, isLoading: false }),
  clearAuth:  () =>
    set({ user: null, accessToken: null, refreshToken: null, isLoading: false }),
  setLoading: (loading) => set({ isLoading: loading }),
  setUser:    (user)    => set({ user }),
}));
