// types/index.ts — Phoenix version
// Ecto uses `inserted_at` / `updated_at` instead of `created_at` / `updated_at`

export type UserRole    = 'admin' | 'moderator' | 'user';
export type MessageStatus = 'sending' | 'sent' | 'delivered' | 'read' | 'failed';
export type MessageType = 'text' | 'image' | 'file' | 'system';
export type UserStatus  = 'online' | 'offline' | 'away';
export type RoomType    = 'public' | 'private' | 'direct';

export interface User {
  id: string;
  username: string;
  email: string;
  role: UserRole;
  avatar?: string;
  status: UserStatus;
  last_seen?: string;
  inserted_at: string;
}

export interface Room {
  id: string;
  name: string;
  description?: string;
  type: RoomType;
  owner_id: string;
  member_count: number;
  inserted_at: string;
  last_message?: Message;
  unread_count?: number;
}

export interface Message {
  id: string;
  room_id: string;
  sender_id: string;
  sender?: Pick<User, 'id' | 'username' | 'avatar'>;
  content: string;
  msg_type: MessageType;
  status: MessageStatus;
  thread_id?: string | null;
  thread_count: number;
  reactions: Record<string, string[]>; // emoji → [userId, ...]
  attachments?: FileAttachment[];
  edited: boolean;
  inserted_at: string;
  updated_at?: string;
}

export interface Thread {
  id: string;
  root_message: Message;
  messages: Message[];
  participant_count: number;
}

export interface FileAttachment {
  id: string;
  filename: string;
  file_type: string;
  file_size: number;
  url: string;
  thumbnail_url?: string;
  inserted_at: string;
}

export interface AuthTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

// Phoenix Channel presence types
export interface PresenceMeta {
  status: UserStatus;
  username: string;
  avatar?: string;
  phx_ref: string;
}

export interface PresenceState {
  [userId: string]: { metas: PresenceMeta[] };
}

export interface PresenceDiff {
  joins:  PresenceState;
  leaves: PresenceState;
}
