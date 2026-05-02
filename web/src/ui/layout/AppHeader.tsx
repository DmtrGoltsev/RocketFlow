import { RetroBadge } from '../primitives/RetroBadge';

interface AppHeaderProps {
  eyebrow?: string;
  title: string;
  subtitle?: string;
  chromeText?: string;
}

export function AppHeader({ eyebrow, title, subtitle, chromeText }: AppHeaderProps) {
  return (
    <div className="surface-header">
      <div className="stack stack--tight">
        {eyebrow ? <div className="caps">{eyebrow}</div> : null}
        <div className="surface-title">{title}</div>
        {subtitle ? <div className="surface-subtitle">{subtitle}</div> : null}
      </div>
      {chromeText ? (
        <div className="surface-meta">
          <RetroBadge tone="info">{chromeText}</RetroBadge>
        </div>
      ) : null}
    </div>
  );
}
