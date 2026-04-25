// services/api.ts — Phoenix version
import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';
import { useAuthStore } from '@/store/chat';
import { Room, Message, User, AuthTokens, FileAttachment } from '@/types';

const BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

class ApiService {
  private client: AxiosInstance;
  private isRefreshing = false;
  private refreshQueue: Array<(token: string) => void> = [];

  constructor() {
    this.client = axios.create({
      baseURL: BASE_URL,
      headers: { 'Content-Type': 'application/json' },
      timeout: 15_000,
    });

    // Attach token
    this.client.interceptors.request.use((config) => {
      const token = useAuthStore.getState().accessToken;
      if (token) config.headers.Authorization = `Bearer ${token}`;
      return config;
    });

    // Auto-refresh on 401
    this.client.interceptors.response.use(
      (res) => res,
      async (error) => {
        const orig = error.config as AxiosRequestConfig & { _retry?: boolean };
        if (error.response?.status === 401 && !orig._retry) {
          orig._retry = true;
          try {
            const newToken = await this.refreshAccessToken();
            orig.headers = { ...orig.headers, Authorization: `Bearer ${newToken}` };
            return this.client(orig);
          } catch {
            useAuthStore.getState().clearAuth();
            if (typeof window !== 'undefined') window.location.href = '/auth/login';
          }
        }
        return Promise.reject(error);
      }
    );
  }

  // ── Auth ──────────────────────────────────────────────────────

  async register(username: string, email: string, password: string) {
    // BUG FIX: backend AuthController.register/2 expects %{"user" => attrs}.
    // Was sending {username, email, password} flat which never matched.
    const res = await this.client.post('/auth/register', {
      user: { username, email, password },
    });
    return res.data as { user: User; tokens: AuthTokens };
  }

  async login(email: string, password: string) {
    // Backend AuthController.login/2 expects flat {email, password} — correct.
    const res = await this.client.post('/auth/login', { email, password });
    return res.data as { user: User; tokens: AuthTokens };
  }

  async logout() {
    await this.client.post('/auth/logout');
  }

  async refreshTokens(refreshToken: string) {
    const res = await this.client.post('/auth/refresh', { refresh_token: refreshToken });
    return res.data as AuthTokens;
  }

  // ── Users ──────────────────────────────────────────────────────

  async getUser(id: string) {
    const res = await this.client.get(`/users/${id}`);
    return res.data.data as User;
  }

  async searchUsers(query: string) {
    const res = await this.client.get('/users', { params: { q: query } });
    return res.data.data as User[];
  }

  // ── Rooms ──────────────────────────────────────────────────────

  async getRooms() {
    const res = await this.client.get('/rooms');
    return res.data.data as Room[];
  }

  async getRoom(id: string) {
    const res = await this.client.get(`/rooms/${id}`);
    return res.data.data as Room;
  }

  async createRoom(name: string, type: 'public' | 'private', description?: string) {
    // BUG FIX: backend RoomController.create/2 expects %{"room" => room_params}.
    // Was sending {name, type, description} flat which didn't match the pattern.
    const res = await this.client.post('/rooms', { room: { name, type, description } });
    return res.data.data as Room;
  }

  async joinRoom(id: string) {
    await this.client.post(`/rooms/${id}/join`);
  }

  async leaveRoom(id: string) {
    await this.client.post(`/rooms/${id}/leave`);
  }

  // ── Messages (fallback REST; prefer channel for real-time) ────

  async getRoomMessages(roomId: string, before?: string, limit = 50) {
    const res = await this.client.get(`/rooms/${roomId}/messages`, {
      params: { before, limit },
    });
    return res.data.data as Message[];
  }

  async editMessage(id: string, content: string) {
    // BUG FIX: backend MessageController.update/2 expects
    // %{"message" => %{"content" => content}}. Was sending {content} flat.
    const res = await this.client.patch(`/messages/${id}`, { message: { content } });
    return res.data.data as Message;
  }

  async deleteMessage(id: string) {
    await this.client.delete(`/messages/${id}`);
  }

  async reactToMessage(id: string, reaction: string) {
    // BUG FIX: backend MessageController.react/2 expects %{"emoji" => emoji}.
    // Was sending { reaction } which didn't match.
    await this.client.post(`/messages/${id}/react`, { emoji: reaction });
  }

  async searchMessages(query: string, roomId?: string) {
    const res = await this.client.get('/messages/search', {
      params: { q: query, room_id: roomId },
    });
    return res.data.data as Message[];
  }

  // ── Threads ────────────────────────────────────────────────────

  async getThread(threadId: string) {
    const res = await this.client.get(`/threads/${threadId}`);
    return res.data.data;
  }

  async getThreadMessages(threadId: string) {
    const res = await this.client.get(`/threads/${threadId}/messages`);
    return res.data.data as Message[];
  }

  // ── Files ──────────────────────────────────────────────────────

  async uploadFile(file: File, onProgress?: (pct: number) => void, roomId?: string) {
    const form = new FormData();
    form.append('file', file);
    if (roomId) form.append('room_id', roomId);
    const res = await this.client.post('/files/upload', form, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: (e) => {
        if (onProgress && e.total) {
          onProgress(Math.round((e.loaded / e.total) * 100));
        }
      },
    });
    return res.data.data as FileAttachment;
  }

  // ── Internal ───────────────────────────────────────────────────

  private async refreshAccessToken(): Promise<string> {
    if (this.isRefreshing) {
      return new Promise((resolve) => this.refreshQueue.push(resolve));
    }
    this.isRefreshing = true;
    try {
      const rt = useAuthStore.getState().refreshToken;
      const tokens = await this.refreshTokens(rt!);
      const user = useAuthStore.getState().user!;
      useAuthStore.getState().setAuth(user, tokens.access_token, tokens.refresh_token);
      localStorage.setItem('access_token', tokens.access_token);
      localStorage.setItem('refresh_token', tokens.refresh_token);
      this.refreshQueue.forEach((cb) => cb(tokens.access_token));
      this.refreshQueue = [];
      return tokens.access_token;
    } finally {
      this.isRefreshing = false;
    }
  }
}

export const api = new ApiService();
