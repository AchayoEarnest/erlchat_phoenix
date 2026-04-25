// lib/utils.ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { format, isToday, isYesterday, formatDistanceToNow } from 'date-fns';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

function safeDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
  const str = typeof value === 'string' ? value : JSON.stringify(value);
  const d = new Date(str);
  return isNaN(d.getTime()) ? null : d;
}

export function formatMessageTime(dateStr: unknown): string {
  const date = safeDate(dateStr);
  if (!date) return '';
  return format(date, 'HH:mm');
}

export function formatFullDate(dateStr: unknown): string {
  const date = safeDate(dateStr);
  if (!date) return '';
  if (isToday(date)) return format(date, 'HH:mm');
  if (isYesterday(date)) return `Yesterday at ${format(date, 'HH:mm')}`;
  return format(date, 'MMM d, yyyy HH:mm');
}

export function formatRelative(dateStr: unknown): string {
  const date = safeDate(dateStr);
  if (!date) return '';
  return formatDistanceToNow(date, { addSuffix: true });
}

export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

export function debounce<T extends (...args: unknown[]) => void>(fn: T, ms: number): T {
  let timer: ReturnType<typeof setTimeout>;
  return ((...args: unknown[]) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  }) as T;
}
