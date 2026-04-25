// components/AuthInitializer.tsx
// Restores auth state from localStorage on every page load so
// isLoading doesn't stay true forever on refresh.
'use client';
import { useEffect } from 'react';
import { useAuthStore } from '@/store/chat';

export function AuthInitializer() {
  useEffect(() => {
    const accessToken  = localStorage.getItem('access_token');
    const refreshToken = localStorage.getItem('refresh_token');
    const userRaw      = localStorage.getItem('user');

    if (accessToken && refreshToken && userRaw) {
      try {
        const user = JSON.parse(userRaw);
        useAuthStore.getState().setAuth(user, accessToken, refreshToken);
      } catch {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        localStorage.removeItem('user');
        useAuthStore.getState().clearAuth();
      }
    } else {
      useAuthStore.getState().clearAuth();
    }
  }, []);

  return null;
}
