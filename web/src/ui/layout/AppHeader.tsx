import { RetroBadge } from '../primitives/RetroBadge';

interface AppHeaderProps {
  eyebrow: string;
  title: string;
  subtitle: string;
  chromeText: string;
}

export function AppHeader({ eyebrow, title, subtitle, chromeText }: AppHeaderProps) {
  return (
    <div className="surface-header">
      <div className="stack stack--tight">
        <div className="caps">{eyebrow}</div>
        <div className="surface-title">{title}</div>
        <div className="surface-subtitle">{subtitle}</div>
      </div>
      <div className="surface-meta">
        <RetroBadge tone="info">{chromeText}</RetroBadge>
        <RetroBadge tone="success">Retro</RetroBadge>
      </div>
    </div>
  );
}
