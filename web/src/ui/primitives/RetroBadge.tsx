type BadgeTone = 'info' | 'success' | 'warning' | 'danger';

interface RetroBadgeProps {
  children: string;
  tone?: BadgeTone;
}

export function RetroBadge({ children, tone = 'info' }: RetroBadgeProps) {
  return <span className={`retro-badge retro-badge--${tone}`}>{children}</span>;
}
