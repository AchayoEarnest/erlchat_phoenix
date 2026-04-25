// components/chat/MessageInput.tsx
'use client';
import { useState, useCallback, useRef, useEffect } from 'react';
import { Paperclip, Send, X } from 'lucide-react';
import { api } from '@/services/api';
import { cn } from '@/lib/utils';
import toast from 'react-hot-toast';
import { FileAttachment } from '@/types';

interface Props {
  roomId: string;
  roomName: string;
  onSend: (content: string, threadId?: string) => void;
  onTyping: (roomId: string, isTyping: boolean) => void;
  threadId?: string;
  placeholder?: string;
}

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50 MB
const ALLOWED_TYPES = [
  'image/jpeg', 'image/png', 'image/gif', 'image/webp',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
];

export function MessageInput({ roomId, roomName, onSend, onTyping, threadId, placeholder }: Props) {
  const [content, setContent] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [pendingFiles, setPendingFiles] = useState<FileAttachment[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isTypingRef = useRef(false);

  // Auto-resize textarea
  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = 'auto';
    ta.style.height = Math.min(ta.scrollHeight, 200) + 'px';
  }, [content]);

  const handleTyping = useCallback(() => {
    if (!isTypingRef.current) {
      isTypingRef.current = true;
      onTyping(roomId, true);
    }
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(() => {
      isTypingRef.current = false;
      onTyping(roomId, false);
    }, 2000);
  }, [roomId, onTyping]);

  const handleSend = useCallback(() => {
    const text = content.trim();
    if (!text && pendingFiles.length === 0) return;

    // Stop typing indicator
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    if (isTypingRef.current) {
      isTypingRef.current = false;
      onTyping(roomId, false);
    }

    onSend(text, threadId);
    setContent('');
    setPendingFiles([]);
    if (textareaRef.current) textareaRef.current.style.height = 'auto';
  }, [content, pendingFiles, onSend, onTyping, roomId, threadId]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (!files.length) return;

    for (const file of files) {
      if (file.size > MAX_FILE_SIZE) {
        toast.error(`${file.name} exceeds 50MB limit`);
        continue;
      }
      if (!ALLOWED_TYPES.includes(file.type)) {
        toast.error(`${file.name}: unsupported file type`);
        continue;
      }

      setIsUploading(true);
      try {
        const attachment = await api.uploadFile(file, setUploadProgress, roomId);
        setPendingFiles(prev => [...prev, attachment]);
      } catch (err) {
        toast.error(`Failed to upload ${file.name}`);
      } finally {
        setIsUploading(false);
        setUploadProgress(0);
      }
    }

    // Reset file input
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const removePendingFile = (id: string) => {
    setPendingFiles(prev => prev.filter(f => f.id !== id));
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    const files = Array.from(e.dataTransfer.files);
    if (fileInputRef.current) {
      const dt = new DataTransfer();
      files.forEach(f => dt.items.add(f));
      fileInputRef.current.files = dt.files;
      fileInputRef.current.dispatchEvent(new Event('change', { bubbles: true }));
    }
  };

  return (
    <div
      className="bg-gray-800 border border-gray-700 rounded-xl overflow-hidden"
      onDrop={handleDrop}
      onDragOver={e => e.preventDefault()}
    >
      {/* Pending file previews */}
      {pendingFiles.length > 0 && (
        <div className="flex flex-wrap gap-2 px-3 pt-3">
          {pendingFiles.map(f => (
            <div key={f.id} className="relative group">
              {f.file_type.startsWith('image/') ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={f.thumbnail_url || f.url}
                  alt={f.filename}
                  className="w-16 h-16 object-cover rounded-lg border border-gray-600"
                />
              ) : (
                <div className="px-3 py-2 bg-gray-700 rounded-lg text-xs text-gray-300 flex items-center gap-1.5">
                  📎 <span className="max-w-[100px] truncate">{f.filename}</span>
                </div>
              )}
              <button
                onClick={() => removePendingFile(f.id)}
                className="absolute -top-1.5 -right-1.5 bg-gray-600 hover:bg-red-600 rounded-full p-0.5 opacity-0 group-hover:opacity-100 transition-all"
              >
                <X className="w-2.5 h-2.5" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Upload progress */}
      {isUploading && (
        <div className="px-3 pt-2">
          <div className="bg-gray-700 rounded-full h-1.5">
            <div
              className="bg-indigo-500 h-1.5 rounded-full transition-all"
              style={{ width: `${uploadProgress}%` }}
            />
          </div>
        </div>
      )}

      {/* Input row */}
      <div className="flex items-end gap-2 p-2">
        {/* File attach */}
        <button
          onClick={() => fileInputRef.current?.click()}
          className="flex-shrink-0 p-2 rounded-lg text-gray-500 hover:text-gray-300 hover:bg-gray-700 transition-colors"
        >
          <Paperclip className="w-4 h-4" />
        </button>
        <input
          ref={fileInputRef}
          type="file"
          multiple
          accept={ALLOWED_TYPES.join(',')}
          onChange={handleFileSelect}
          className="hidden"
        />

        {/* Textarea */}
        <textarea
          ref={textareaRef}
          value={content}
          onChange={e => { setContent(e.target.value); handleTyping(); }}
          onKeyDown={handleKeyDown}
          placeholder={placeholder || `Message #${roomName}`}
          rows={1}
          className={cn(
            'flex-1 bg-transparent text-gray-100 placeholder-gray-600 text-sm',
            'resize-none outline-none min-h-[36px] max-h-[200px] py-2 leading-relaxed'
          )}
        />

        {/* Send button */}
        <button
          onClick={handleSend}
          disabled={!content.trim() && pendingFiles.length === 0}
          className={cn(
            'flex-shrink-0 p-2 rounded-lg transition-colors',
            content.trim() || pendingFiles.length > 0
              ? 'bg-indigo-600 hover:bg-indigo-500 text-white'
              : 'text-gray-600 cursor-not-allowed'
          )}
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}
