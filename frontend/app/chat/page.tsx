// app/chat/page.tsx - Main chat application page
'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuthStore, useChatStore } from '@/store/chat';
import { useWebSocket } from '@/hooks/useWebSocket';
import { api } from '@/services/api';
import { Sidebar } from '@/components/layout/Sidebar';
import { ChatWindow } from '@/components/chat/ChatWindow';
import { ThreadPanel } from '@/components/chat/ThreadPanel';
import { cn } from '@/lib/utils';

export default function ChatPage() {
  const router = useRouter();
  const { user, isLoading, accessToken } = useAuthStore();
  const { activeRoomId, threadPanelOpen, setRooms } = useChatStore();
  useWebSocket(); // Connects WS and wires events to store

  // Guard: redirect to login if not authed
  useEffect(() => {
    if (!isLoading && !user) {
      router.push('/auth/login');
    }
  }, [isLoading, user, router]);

  // Load user's rooms on mount
  useEffect(() => {
    if (!accessToken) return;
    api.getRooms()
      .then(setRooms)
      .catch(console.error);
  }, [accessToken, setRooms]);

  if (isLoading) {
    return (
      <div className="h-screen flex items-center justify-center bg-gray-950">
        <div className="text-center space-y-3">
          <div className="w-10 h-10 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin mx-auto" />
          <p className="text-gray-400 text-sm">Loading ErlChat…</p>
        </div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <div className="h-screen flex overflow-hidden bg-gray-950">
      {/* Left sidebar: rooms + DMs */}
      <Sidebar />

      {/* Main chat area */}
      <main className={cn(
        'flex-1 flex flex-col min-w-0 transition-all duration-200',
        threadPanelOpen ? 'mr-[340px]' : ''
      )}>
        {activeRoomId ? (
          <ChatWindow roomId={activeRoomId} />
        ) : (
          <EmptyState />
        )}
      </main>

      {/* Thread panel (right side) */}
      {threadPanelOpen && <ThreadPanel />}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex-1 flex flex-col items-center justify-center text-center px-8">
      <div className="w-16 h-16 rounded-2xl bg-indigo-600/20 flex items-center justify-center mb-4">
        <svg className="w-8 h-8 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
        </svg>
      </div>
      <h2 className="text-xl font-semibold text-gray-100 mb-2">Welcome to ErlChat</h2>
      <p className="text-gray-400 text-sm max-w-sm">
        Select a room or direct message from the sidebar to start chatting.
      </p>
    </div>
  );
}
