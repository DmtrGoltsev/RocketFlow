import type { ReactNode } from 'react';

interface RetroDialogFrameProps {
  title: string;
  children: ReactNode;
  footer?: ReactNode;
}

export function RetroDialogFrame({ title, children, footer }: RetroDialogFrameProps) {
  return (
    <div className="retro-panel">
      <div className="retro-panel__header">
        <div className="retro-panel__title">{title}</div>
      </div>
      <div className="retro-panel__body stack">
        {children}
        {footer ? <div className="spacer-line" /> : null}
        {footer}
      </div>
    </div>
  );
}
