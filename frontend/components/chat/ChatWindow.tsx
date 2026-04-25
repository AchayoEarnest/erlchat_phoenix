// components/chat/ChatWindow.tsx — Phoenix version
// Key difference: pagination uses the "load_messages" channel event
// instead of REST, keeping everything over one WebSocket connection.
'use client';
import { useEffect, useRef, useCallback, useState } from 'react';
import { useChatStore, useAuthStore } from '@/store/chat';
import { useWebSocket } from '@/hooks/useWebSocket';
import { MessageItem } from './MessageItem';
import { MessageInput } from './MessageInput';
import { TypingIndicator } from './TypingIndicator';
import { useIntersectionObserver } from '@/hooks/useIntersectionObserver';
import { Hash, Lock, Users, Search } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Message } from '@/types';

interface Props { roomId: string; }

export function ChatWindow({ roomId }: Props) {
  const { rooms, messages, prependMessages } = useChatStore();
  const { user } = useAuthStore();
  const { sendMessage, sendTyping, loadMessages, joinRoom, leaveRoom } = useWebSocket();

  const room = rooms[roomId];
  const roomMessages = messages[roomId] || [];

  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [channelReady, setChannelReady] = useState(false);
  const bottomRef   = useRef<HTMLDivElement>(null);
  const topRef      = useRef<HTMLDivElement>(null);
  const scrollRef   = useRef<HTMLDivElement>(null);
  const isAtBottom  = useRef(true);

  // Join the Phoenix channel when this room mounts, leave when it unmounts
  useEffect(() => {
    setChannelReady(false);
    setHasMore(true);
    joinRoom(roomId);
    // Give the channel a moment to complete its join handshake
    const t = setTimeout(() => setChannelReady(true), 500);
    return () => {
      clearTimeout(t);
      leaveRoom(roomId);
      setChannelReady(false);
    };
  }, [roomId, joinRoom, leaveRoom]);

  // Scroll to bottom when new messages arrive (if already at bottom)
  useEffect(() => {
    if (isAtBottom.current) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [roomMessages.length]);

  // Infinite scroll — load older messages via channel push
  const handleTopVisible = useCallback(async () => {
    if (!channelReady || !hasMore || isLoadingMore || roomMessages.length === 0) return;

    const oldest     = roomMessages[0] as Message;
    const prevHeight = scrollRef.current?.scrollHeight || 0;
    setIsLoadingMore(true);

    try {
      const { messages: older } = await loadMessages(
        roomId,
        oldest.inserted_at as unknown as string
      );

      if (!older || older.length === 0) {
        setHasMore(false);
        return;
      }

      prependMessages(roomId, older);

      // Maintain scroll position
      requestAnimationFrame(() => {
        const el = scrollRef.current;
        if (el) el.scrollTop = el.scrollHeight - prevHeight;
      });
    } catch (err) {
      console.error('[ChatWindow] Failed to load older messages:', err);
    } finally {
      setIsLoadingMore(false);
    }
  }, [channelReady, hasMore, isLoadingMore, roomId, roomMessages, loadMessages, prependMessages]);

  useIntersectionObserver(topRef, handleTopVisible, { threshold: 0.1 });

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    isAtBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 100;
  };

  const handleSend = useCallback((content: string, threadId?: string) => {
    if (!content.trim()) return;
    sendMessage(roomId, content, threadId);
  }, [roomId, sendMessage]);

  if (!room) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="w-6 h-6 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Room header */}
      <header className="h-[52px] border-b border-gray-800 flex items-center justify-between px-4 flex-shrink-0">
        <div className="flex items-center gap-2">
          {room.type === 'private'
            ? <Lock className="w-4 h-4 text-gray-400" />
            : <Hash className="w-4 h-4 text-gray-400" />
          }
          <h1 className="font-semibold text-gray-100 text-sm">{room.name}</h1>
          {room.description && (
            <>
              <span className="text-gray-700">|</span>
              <p className="text-gray-500 text-xs truncate max-w-sm">{room.description}</p>
            </>
          )}
        </div>
        <div className="flex items-center gap-2">
          <button className="btn-ghost p-1.5 rounded-lg"><Search className="w-4 h-4" /></button>
          <button className="btn-ghost p-1.5 rounded-lg"><Users className="w-4 h-4" /></button>
          <span className="text-xs text-gray-500 ml-1">{room.member_count} members</span>
        </div>
      </header>

      {/* Message list */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto px-4 py-2 space-y-0.5"
      >
        <div ref={topRef} className="h-1" />

        {isLoadingMore && (
          <div className="flex justify-center py-3">
            <div className="w-4 h-4 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
          </div>
        )}

        {!hasMore && roomMessages.length > 0 && (
          <div className="text-center py-4">
            <p className="text-xs text-gray-600">— Beginning of #{room.name} —</p>
          </div>
        )}

        {roomMessages.map((msg, idx) => {
          const prev = roomMessages[idx - 1];
          const isGrouped =
            prev &&
            (prev as Message).sender_id === (msg as Message).sender_id &&
            new Date((msg as Message).inserted_at as unknown as string).getTime() -
              new Date((prev as Message).inserted_at as unknown as string).getTime() < 300_000;

          return (
            <MessageItem
              key={(msg as Message).id}
              message={msg as Message}
              isOwn={(msg as Message).sender_id === user?.id}
              isGrouped={!!isGrouped}
              roomId={roomId}
            />
          );
        })}

        <TypingIndicator roomId={roomId} />
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="flex-shrink-0 px-4 pb-4 pt-2">
        <MessageInput
          roomId={roomId}
          roomName={room.name}
          onSend={handleSend}
          onTyping={sendTyping}
        />
      </div>
    </div>
  );
}
