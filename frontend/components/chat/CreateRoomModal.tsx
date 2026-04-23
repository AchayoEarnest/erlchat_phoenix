// components/chat/CreateRoomModal.tsx
'use client';
import { useState } from 'react';
import { api } from '@/services/api';
import { useChatStore } from '@/store/chat';
import { X, Hash, Lock } from 'lucide-react';
import { wsService } from '@/services/phoenix-socket';
import toast from 'react-hot-toast';
import { cn } from '@/lib/utils';

export function CreateRoomModal({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [type, setType] = useState<'public' | 'private'>('public');
  const [isLoading, setIsLoading] = useState(false);
  const { addRoom, setActiveRoom } = useChatStore();

  const handleCreate = async () => {
    if (!name.trim()) return;
    setIsLoading(true);
    try {
      const room = await api.createRoom(name.trim(), type, description.trim() || undefined);
      addRoom(room);
      setActiveRoom(room.id);
      wsService.send({ type: 'join_room', room_id: room.id });
      toast.success(`#${room.name} created`);
      onClose();
    } catch (err) {
      toast.error('Failed to create room');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 animate-fade-in">
      <div className="bg-gray-900 border border-gray-800 rounded-2xl w-full max-w-md p-6 shadow-2xl animate-slide-up">
        <div className="flex items-center justify-between mb-5">
          <h2 className="text-lg font-semibold text-gray-100">Create a channel</h2>
          <button onClick={onClose} className="btn-ghost p-1 rounded">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Type selector */}
        <div className="grid grid-cols-2 gap-2 mb-4">
          {(['public', 'private'] as const).map(t => (
            <button
              key={t}
              onClick={() => setType(t)}
              className={cn(
                'flex items-center gap-2 p-3 rounded-xl border text-sm font-medium transition-all',
                type === t
                  ? 'border-indigo-500 bg-indigo-600/20 text-indigo-300'
                  : 'border-gray-700 text-gray-400 hover:border-gray-600'
              )}
            >
              {t === 'public' ? <Hash className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
              {t.charAt(0).toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>

        {/* Name */}
        <div className="mb-3">
          <label className="block text-xs font-medium text-gray-400 mb-1.5">Channel name</label>
          <div className="relative">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">
              {type === 'public' ? '#' : '🔒'}
            </span>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value.toLowerCase().replace(/\s+/g, '-'))}
              placeholder="e.g. general"
              className="input-field w-full pl-8"
              maxLength={64}
              autoFocus
            />
          </div>
        </div>

        {/* Description */}
        <div className="mb-5">
          <label className="block text-xs font-medium text-gray-400 mb-1.5">Description <span className="text-gray-600">(optional)</span></label>
          <input
            type="text"
            value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="What's this channel about?"
            className="input-field w-full"
            maxLength={256}
          />
        </div>

        <div className="flex gap-2 justify-end">
          <button onClick={onClose} className="btn-ghost px-4 py-2">Cancel</button>
          <button
            onClick={handleCreate}
            disabled={!name.trim() || isLoading}
            className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isLoading ? 'Creating…' : 'Create channel'}
          </button>
        </div>
      </div>
    </div>
  );
}
