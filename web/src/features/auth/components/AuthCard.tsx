import { Link } from 'react-router-dom';

import { RetroBadge } from '../../../ui/primitives/RetroBadge';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';

interface AuthCardProps {
  title: string;
  subtitle: string;
  alternatePrompt: string;
  alternateAction: string;
  alternateTo: string;
  children: React.ReactNode;
}

export function AuthCard({
  title,
  subtitle,
  alternatePrompt,
  alternateAction,
  alternateTo,
  children
}: AuthCardProps) {
  return (
    <RetroPanel
      title={title}
      aside={<RetroBadge tone="info">Auth</RetroBadge>}
    >
      <div className="stack">
        <div className="surface-subtitle">{subtitle}</div>
        {children}
        <div className="cluster">
          <span className="muted">{alternatePrompt}</span>
          <Link to={alternateTo}>{alternateAction}</Link>
        </div>
      </div>
    </RetroPanel>
  );
}

