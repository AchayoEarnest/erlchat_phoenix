// components/chat/TypingIndicator.tsx
'use client';
import { useChatStore } from '@/store/chat';

export function TypingIndicator({ roomId }: { roomId: string }) {
  const { typingUsers, userCache } = useChatStore();
  const typers = Array.from(typingUsers[roomId] || []);
  if (typers.length === 0) return null;

  const names = typers
    .slice(0, 3)
    .map(id => userCache[id]?.username || id.slice(0, 6));

  const label =
    names.length === 1 ? `${names[0]} is typing…`
    : names.length === 2 ? `${names[0]} and ${names[1]} are typing…`
    : `${names[0]}, ${names[1]} and others are typing…`;

  return (
    <div className="flex items-center gap-2 px-1 py-1 text-gray-500 text-xs h-6">
      <div className="flex gap-0.5">
        <span className="typing-dot w-1.5 h-1.5 bg-gray-500 rounded-full" />
        <span className="typing-dot w-1.5 h-1.5 bg-gray-500 rounded-full" />
        <span className="typing-dot w-1.5 h-1.5 bg-gray-500 rounded-full" />
      </div>
      <span>{label}</span>
    </div>
  );
}
