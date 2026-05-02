import { Link } from 'react-router-dom';

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
    <section className="auth-panel">
      <div className="stack stack--tight">
        <div className="wordmark">RocketFlow</div>
        <h1 className="auth-panel__title">{title}</h1>
        <p className="auth-panel__copy">{subtitle}</p>
      </div>
      {children}
      <div className="auth-panel__alternate">
        <span>{alternatePrompt}</span>
        <Link to={alternateTo}>{alternateAction}</Link>
      </div>
    </section>
  );
}
