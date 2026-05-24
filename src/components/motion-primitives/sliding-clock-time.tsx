import { cn } from '@/components/ui/utils';
import type { SlidingClockTimeProps } from '@/components/motion-primitives/slidingClockTime.shared';

export function SlidingClockTime({ time, className }: SlidingClockTimeProps) {
  return <span className={cn('tabular-nums', className)}>{time}</span>;
}
