// hooks/usePhoenixChannel.ts
// Drop-in replacement for useWebSocket.ts — same interface, Phoenix backend.
'use client';
import { useEffect, useCallback, useRef } from 'react';
import { phoenixSocket } from '@/services/phoenix-socket';
import { useAuthStore, useChatStore } from '@/store/chat';

export function useWebSocket() {
  const { accessToken, user } = useAuthStore();
  const connected = useRef(false);

  // Connect socket once on mount when token is available
  useEffect(() => {
    if (!accessToken || connected.current) return;
    connected.current = true;

    phoenixSocket
      .connect(accessToken)
      .catch((err) => {
        console.error('[Phoenix] Connection failed:', err);
        connected.current = false;
      });

    return () => {
      // Don't disconnect on re-render — only on actual logout
    };
  }, [accessToken]);

  // Re-connect if token changes (e.g. after refresh)
  useEffect(() => {
    if (!accessToken) {
      phoenixSocket.disconnect();
      connected.current = false;
    }
  }, [accessToken]);

  const sendMessage = useCallback(
    (roomId: string, content: string, threadId?: string) => {
      return phoenixSocket.sendMessage(roomId, content, threadId);
    },
    []
  );

  const sendTyping = useCallback((roomId: string, isTyping: boolean) => {
    phoenixSocket.sendTyping(roomId, isTyping);
  }, []);

  const joinRoom = useCallback((roomId: string) => {
    phoenixSocket.joinRoom(roomId);
  }, []);

  const leaveRoom = useCallback((roomId: string) => {
    phoenixSocket.leaveRoom(roomId);
  }, []);

  const sendReadReceipt = useCallback((roomId: string, messageId: string) => {
    phoenixSocket.sendReadReceipt(roomId, messageId);
  }, []);

  const loadMessages = useCallback((roomId: string, before?: string) => {
    return phoenixSocket.loadMessages(roomId, before);
  }, []);

  return {
    isConnected: phoenixSocket.isConnected,
    sendMessage,
    sendTyping,
    joinRoom,
    leaveRoom,
    sendReadReceipt,
    loadMessages,
  };
}
