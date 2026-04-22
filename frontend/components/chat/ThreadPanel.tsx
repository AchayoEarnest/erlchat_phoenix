// components/chat/ThreadPanel.tsx
'use client';
import { useEffect, useState } from 'react';
import { useChatStore, useAuthStore } from '@/store/chat';
import { useWebSocket } from '@/hooks/useWebSocket';
import { api } from '@/services/api';
import { MessageItem } from './MessageItem';
import { MessageInput } from './MessageInput';
import { Message } from '@/types';
import { X } from 'lucide-react';

export function ThreadPanel() {
  const { activeThread, setActiveThread, setThreadPanelOpen } = useChatStore();
  const { sendMessage, sendTyping } = useWebSocket();
  const [replies, setReplies] = useState<Message[]>([]);
  const { user } = useAuthStore();

  useEffect(() => {
    if (!activeThread?.root_message.id) return;
    api.getThreadMessages(activeThread.root_message.id)
      .then(setReplies)
      .catch(console.error);
  }, [activeThread?.root_message.id]);

  if (!activeThread) return null;

  const handleSend = (content: string) => {
    sendMessage(
      activeThread.root_message.room_id,
      content,
      activeThread.root_message.id
    );
  };

  return (
    <aside className="fixed right-0 top-0 h-full w-[340px] bg-gray-900 border-l border-gray-800 flex flex-col animate-slide-in-right z-30">
      <header className="h-[52px] flex items-center justify-between px-4 border-b border-gray-800">
        <h2 className="font-semibold text-gray-100 text-sm">Thread</h2>
        <button
          onClick={() => { setActiveThread(null); setThreadPanelOpen(false); }}
          className="btn-ghost p-1 rounded"
        >
          <X className="w-4 h-4" />
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-1">
        {/* Root message */}
        <MessageItem
          message={activeThread.root_message}
          isOwn={activeThread.root_message.sender_id === user?.id}
          isGrouped={false}
          roomId={activeThread.root_message.room_id}
        />

        {replies.length > 0 && (
          <>
            <div className="flex items-center gap-2 my-4">
              <hr className="flex-1 border-gray-800" />
              <span className="text-xs text-gray-600">{replies.length} {replies.length === 1 ? 'reply' : 'replies'}</span>
              <hr className="flex-1 border-gray-800" />
            </div>
            {replies.map((msg, idx) => (
              <MessageItem
                key={msg.id}
                message={msg}
                isOwn={msg.sender_id === user?.id}
                isGrouped={idx > 0 && replies[idx-1].sender_id === msg.sender_id}
                roomId={msg.room_id}
              />
            ))}
          </>
        )}
      </div>

      <div className="p-3 border-t border-gray-800">
        <MessageInput
          roomId={activeThread.root_message.room_id}
          roomName="thread"
          onSend={handleSend}
          onTyping={sendTyping}
          threadId={activeThread.root_message.id}
          placeholder="Reply in thread…"
        />
      </div>
    </aside>
  );
}
