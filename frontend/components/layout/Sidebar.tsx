// components/layout/Sidebar.tsx
'use client';
import { useState, useCallback } from 'react';
import { useAuthStore, useChatStore } from '@/store/chat';
import { useWebSocket } from '@/hooks/useWebSocket';
import { api } from '@/services/api';
import { Room } from '@/types';
import { cn } from '@/lib/utils';
import { Hash, Lock, MessageCircle, Plus, LogOut, Settings, Search, ChevronDown } from 'lucide-react';
import { Avatar } from '@/components/ui/Avatar';
import { CreateRoomModal } from '@/components/chat/CreateRoomModal';
import { wsService } from '@/services/websocket';
import { useRouter } from 'next/navigation';

export function Sidebar() {
  const router = useRouter();
  const { user, clearAuth } = useAuthStore();
  const { rooms, activeRoomId, setActiveRoom, onlineUsers } = useChatStore();
  const { joinRoom } = useWebSocket();
  const [showCreateRoom, setShowCreateRoom] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [roomsExpanded, setRoomsExpanded] = useState(true);
  const [dmsExpanded, setDmsExpanded] = useState(true);

  const roomList = Object.values(rooms);
  const publicRooms = roomList.filter(r => r.type === 'public' || r.type === 'private');
  const dmRooms     = roomList.filter(r => r.type === 'direct');

  const filtered = (list: Room[]) =>
    searchQuery
      ? list.filter(r => r.name.toLowerCase().includes(searchQuery.toLowerCase()))
      : list;

  const handleSelectRoom = useCallback((room: Room) => {
    setActiveRoom(room.id);
    joinRoom(room.id);
  }, [setActiveRoom, joinRoom]);

  const handleLogout = async () => {
    try {
      await api.logout();
    } catch {}
    wsService.disconnect();
    clearAuth();
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    router.push('/auth/login');
  };

  const userStatus = user ? (onlineUsers[user.id] || 'online') : 'offline';

  return (
    <>
      <aside className="w-[260px] flex-shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col h-full">
        {/* Workspace header */}
        <div className="h-[52px] flex items-center justify-between px-4 border-b border-gray-800">
          <span className="font-semibold text-gray-100 text-sm tracking-wide">ErlChat</span>
          <button className="btn-ghost p-1 rounded" onClick={() => setShowCreateRoom(true)}>
            <Plus className="w-4 h-4" />
          </button>
        </div>

        {/* Search */}
        <div className="px-3 pt-3 pb-2">
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-500" />
            <input
              type="text"
              placeholder="Search rooms…"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="input-field w-full py-1.5 pl-8 pr-3 text-xs"
            />
          </div>
        </div>

        {/* Nav list */}
        <nav className="flex-1 overflow-y-auto px-2 space-y-0.5 py-1">
          {/* Channels section */}
          <SectionHeader
            label="Channels"
            expanded={roomsExpanded}
            onToggle={() => setRoomsExpanded(v => !v)}
            onAdd={() => setShowCreateRoom(true)}
          />
          {roomsExpanded && filtered(publicRooms).map(room => (
            <RoomItem
              key={room.id}
              room={room}
              active={room.id === activeRoomId}
              onClick={() => handleSelectRoom(room)}
            />
          ))}

          {/* DMs section */}
          <div className="mt-3">
            <SectionHeader
              label="Direct Messages"
              expanded={dmsExpanded}
              onToggle={() => setDmsExpanded(v => !v)}
              onAdd={() => {}}
            />
            {dmsExpanded && filtered(dmRooms).map(room => (
              <RoomItem
                key={room.id}
                room={room}
                active={room.id === activeRoomId}
                onClick={() => handleSelectRoom(room)}
                isDm
              />
            ))}
          </div>
        </nav>

        {/* User footer */}
        <div className="border-t border-gray-800 p-3 flex items-center gap-2">
          <div className="relative flex-shrink-0">
            <Avatar
              name={user?.username || '?'}
              src={user?.avatar}
              size="sm"
            />
            <span className={cn(
              'absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-gray-900',
              userStatus === 'online' ? 'bg-green-400' : 'bg-gray-500'
            )} />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-gray-100 truncate">{user?.username}</p>
            <p className="text-xs text-gray-500 truncate">{user?.role}</p>
          </div>
          <div className="flex items-center gap-1">
            <button className="btn-ghost p-1 rounded" title="Settings">
              <Settings className="w-3.5 h-3.5" />
            </button>
            <button className="btn-ghost p-1 rounded text-red-400 hover:text-red-300"
              title="Logout" onClick={handleLogout}>
              <LogOut className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      </aside>

      {showCreateRoom && (
        <CreateRoomModal onClose={() => setShowCreateRoom(false)} />
      )}
    </>
  );
}

function SectionHeader({
  label, expanded, onToggle, onAdd
}: { label: string; expanded: boolean; onToggle: () => void; onAdd: () => void }) {
  return (
    <div className="flex items-center justify-between px-2 py-1 group">
      <button
        onClick={onToggle}
        className="flex items-center gap-1 text-xs font-semibold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
      >
        <ChevronDown className={cn('w-3 h-3 transition-transform', !expanded && '-rotate-90')} />
        {label}
      </button>
      <button
        onClick={onAdd}
        className="opacity-0 group-hover:opacity-100 p-0.5 rounded text-gray-500 hover:text-gray-300 transition-opacity"
      >
        <Plus className="w-3 h-3" />
      </button>
    </div>
  );
}

function RoomItem({
  room, active, onClick, isDm
}: { room: Room; active: boolean; onClick: () => void; isDm?: boolean }) {
  const { onlineUsers } = useChatStore();
  const Icon = isDm ? MessageCircle : (room.type === 'private' ? Lock : Hash);

  return (
    <button
      onClick={onClick}
      className={cn('sidebar-item w-full', active && 'sidebar-item-active')}
    >
      <Icon className="w-3.5 h-3.5 flex-shrink-0" />
      <span className="truncate flex-1 text-left">{room.name}</span>
      {room.unread_count && room.unread_count > 0 && (
        <span className="ml-auto bg-indigo-600 text-white text-xs rounded-full px-1.5 py-0.5 min-w-[18px] text-center">
          {room.unread_count > 99 ? '99+' : room.unread_count}
        </span>
      )}
    </button>
  );
}
