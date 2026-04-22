// components/chat/MessageItem.tsx
'use client';
import { useState, useCallback } from 'react';
import { Message } from '@/types';
import { useChatStore, useAuthStore } from '@/store/chat';
import { api } from '@/services/api';
import { wsService } from '@/services/websocket';
import { Avatar } from '@/components/ui/Avatar';
import { formatMessageTime, formatFullDate } from '@/lib/utils';
import {
  Smile, MoreHorizontal, Reply, Edit2, Trash2, MessageSquare, Check, CheckCheck
} from 'lucide-react';
import dynamic from 'next/dynamic';
import { cn } from '@/lib/utils';

const EmojiPicker = dynamic(() => import('emoji-picker-react'), { ssr: false });

interface Props {
  message: Message;
  isOwn: boolean;
  isGrouped: boolean;
  roomId: string;
}

export function MessageItem({ message, isOwn, isGrouped, roomId }: Props) {
  const { updateMessage, deleteMessage, addReaction, setActiveThread, userCache } = useChatStore();
  const { user } = useAuthStore();
  const [isEditing, setIsEditing] = useState(false);
  const [editContent, setEditContent] = useState(message.content);
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);

  const sender = userCache[message.sender_id];
  const senderName = sender?.username || message.sender_id.slice(0, 8);

  const handleEdit = useCallback(async () => {
    if (editContent.trim() === message.content) {
      setIsEditing(false);
      return;
    }
    try {
      const updated = await api.editMessage(message.id, editContent.trim());
      updateMessage(roomId, message.id, { content: updated.content, edited: true });
      // Broadcast via WS
      wsService.send({ type: 'message_edited', ...updated });
    } catch (err) {
      console.error(err);
    } finally {
      setIsEditing(false);
    }
  }, [editContent, message, roomId, updateMessage]);

  const handleDelete = useCallback(async () => {
    if (!confirm('Delete this message?')) return;
    try {
      await api.deleteMessage(message.id);
      deleteMessage(roomId, message.id);
      wsService.send({ type: 'message_deleted', id: message.id, room_id: roomId });
    } catch (err) {
      console.error(err);
    }
  }, [message.id, roomId, deleteMessage]);

  const handleReact = useCallback(async (emoji: string) => {
    setShowEmojiPicker(false);
    try {
      await api.reactToMessage(message.id, emoji);
      addReaction(roomId, message.id, emoji, user!.id);
      wsService.send({
        type: 'reaction',
        message_id: message.id,
        reaction: emoji,
        user_id: user!.id,
        room_id: roomId,
      });
    } catch (err) {
      console.error(err);
    }
  }, [message.id, roomId, user, addReaction]);

  const handleOpenThread = useCallback(() => {
    setActiveThread({
      id: message.id,
      root_message: message,
      messages: [],
      participant_count: 0,
    });
  }, [message, setActiveThread]);

  const statusIcon = {
    sending:   <div className="w-3 h-3 border border-gray-600 rounded-full animate-spin" />,
    sent:      <Check className="w-3 h-3 text-gray-500" />,
    delivered: <CheckCheck className="w-3 h-3 text-gray-500" />,
    read:      <CheckCheck className="w-3 h-3 text-indigo-400" />,
    failed:    <span className="text-red-400 text-xs">!</span>,
  }[message.status] || null;

  return (
    <div className={cn(
      'group flex gap-3 px-1 py-0.5 rounded-lg hover:bg-gray-900/60 message-row',
      isGrouped ? 'mt-0.5' : 'mt-3'
    )}>
      {/* Avatar / time gutter */}
      <div className="w-9 flex-shrink-0 flex flex-col items-center pt-0.5">
        {isGrouped ? (
          <span className="text-gray-700 text-[10px] opacity-0 group-hover:opacity-100 mt-1">
            {formatMessageTime(message.created_at)}
          </span>
        ) : (
          <Avatar name={senderName} src={sender?.avatar} size="sm" />
        )}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        {/* Sender header (only on first in group) */}
        {!isGrouped && (
          <div className="flex items-baseline gap-2 mb-0.5">
            <span className="font-semibold text-gray-100 text-sm">{senderName}</span>
            <span className="text-gray-600 text-xs">{formatFullDate(message.created_at)}</span>
            {message.edited && (
              <span className="text-gray-700 text-[10px]">(edited)</span>
            )}
          </div>
        )}

        {/* Message body */}
        {isEditing ? (
          <div className="mt-1">
            <input
              autoFocus
              value={editContent}
              onChange={e => setEditContent(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleEdit(); }
                if (e.key === 'Escape') { setIsEditing(false); setEditContent(message.content); }
              }}
              className="input-field w-full text-sm py-1.5"
            />
            <p className="text-xs text-gray-600 mt-1">
              Enter to save · Esc to cancel
            </p>
          </div>
        ) : (
          <p className={cn(
            'text-sm text-gray-200 break-words leading-relaxed whitespace-pre-wrap',
            message.status === 'sending' && 'opacity-60'
          )}>
            <MessageContent content={message.content} />
          </p>
        )}

        {/* Attachments */}
        {message.attachments?.map(att => (
          <FilePreview key={att.id} attachment={att} />
        ))}

        {/* Reactions */}
        {message.reactions && Object.keys(message.reactions).length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1.5">
            {Object.entries(message.reactions).map(([emoji, users]) => (
              <button
                key={emoji}
                onClick={() => handleReact(emoji)}
                className={cn(
                  'flex items-center gap-1 text-xs px-2 py-0.5 rounded-full border transition-colors',
                  users.includes(user?.id || '')
                    ? 'bg-indigo-600/20 border-indigo-500/50 text-indigo-300'
                    : 'bg-gray-800 border-gray-700 text-gray-400 hover:border-gray-600'
                )}
              >
                {emoji} <span>{users.length}</span>
              </button>
            ))}
          </div>
        )}

        {/* Thread reply count */}
        {(message.thread_count || 0) > 0 && (
          <button
            onClick={handleOpenThread}
            className="mt-1.5 text-xs text-indigo-400 hover:text-indigo-300 flex items-center gap-1"
          >
            <MessageSquare className="w-3 h-3" />
            {message.thread_count} {message.thread_count === 1 ? 'reply' : 'replies'}
          </button>
        )}
      </div>

      {/* Hover actions */}
      <div className="message-actions flex items-start gap-0.5 pt-0.5 flex-shrink-0 relative">
        {/* Emoji react */}
        <ActionButton icon={<Smile className="w-3.5 h-3.5" />} onClick={() => setShowEmojiPicker(v => !v)} />

        {/* Thread reply */}
        <ActionButton icon={<Reply className="w-3.5 h-3.5" />} onClick={handleOpenThread} />

        {/* Edit (own messages only) */}
        {isOwn && (
          <ActionButton icon={<Edit2 className="w-3.5 h-3.5" />} onClick={() => setIsEditing(true)} />
        )}

        {/* Delete (own or admin) */}
        {(isOwn || user?.role === 'admin') && (
          <ActionButton
            icon={<Trash2 className="w-3.5 h-3.5 text-red-400" />}
            onClick={handleDelete}
          />
        )}

        {/* Status (own messages) */}
        {isOwn && (
          <div className="flex items-center ml-1 mt-0.5">{statusIcon}</div>
        )}

        {/* Emoji picker dropdown */}
        {showEmojiPicker && (
          <div className="absolute right-0 top-8 z-50">
            <EmojiPicker
              onEmojiClick={(e) => handleReact(e.emoji)}
              skinTonesDisabled
              height={350}
              width={300}
            />
          </div>
        )}
      </div>
    </div>
  );
}

function ActionButton({ icon, onClick }: { icon: React.ReactNode; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="p-1.5 rounded hover:bg-gray-700 text-gray-500 hover:text-gray-300 transition-colors"
    >
      {icon}
    </button>
  );
}

// Parses @mentions and #hashtags with highlight
function MessageContent({ content }: { content: string }) {
  const parts = content.split(/(@\w+|#\w+)/g);
  return (
    <>
      {parts.map((part, i) => {
        if (part.startsWith('@'))
          return <span key={i} className="text-indigo-400 font-medium">{part}</span>;
        if (part.startsWith('#'))
          return <span key={i} className="text-indigo-400">{part}</span>;
        return <span key={i}>{part}</span>;
      })}
    </>
  );
}

function FilePreview({ attachment }: { attachment: { url: string; filename: string; file_type: string; thumbnail_url?: string } }) {
  const isImage = attachment.file_type.startsWith('image/');
  if (isImage) {
    return (
      <div className="mt-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={attachment.thumbnail_url || attachment.url}
          alt={attachment.filename}
          className="max-w-xs max-h-48 rounded-lg border border-gray-700 object-cover cursor-pointer"
        />
      </div>
    );
  }
  return (
    <a
      href={attachment.url}
      target="_blank"
      rel="noopener noreferrer"
      className="mt-2 flex items-center gap-2 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-gray-300 hover:bg-gray-750 w-fit"
    >
      📎 {attachment.filename}
    </a>
  );
}
