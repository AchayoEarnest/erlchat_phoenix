// components/ui/Avatar.tsx
import { cn } from '@/lib/utils';

const COLORS = [
  'bg-red-600', 'bg-orange-600', 'bg-amber-600', 'bg-yellow-600',
  'bg-lime-600', 'bg-green-600', 'bg-emerald-600', 'bg-teal-600',
  'bg-cyan-600', 'bg-sky-600', 'bg-blue-600', 'bg-indigo-600',
  'bg-violet-600', 'bg-purple-600', 'bg-fuchsia-600', 'bg-pink-600',
];

function colorFromName(name: string) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return COLORS[Math.abs(hash) % COLORS.length];
}

interface Props {
  name: string;
  src?: string;
  size?: 'xs' | 'sm' | 'md' | 'lg';
  className?: string;
}

const sizeMap = {
  xs: 'w-5 h-5 text-[8px]',
  sm: 'w-8 h-8 text-xs',
  md: 'w-10 h-10 text-sm',
  lg: 'w-14 h-14 text-lg',
};

export function Avatar({ name, src, size = 'md', className }: Props) {
  const initials = name.split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();
  const color = colorFromName(name);

  if (src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt={name}
        className={cn('rounded-full object-cover flex-shrink-0', sizeMap[size], className)}
      />
    );
  }

  return (
    <div className={cn(
      'rounded-full flex items-center justify-center font-semibold text-white flex-shrink-0',
      sizeMap[size], color, className
    )}>
      {initials}
    </div>
  );
}
