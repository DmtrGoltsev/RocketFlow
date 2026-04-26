import type { PropsWithChildren, ReactNode } from 'react';

interface RetroPanelProps {
  title: string;
  aside?: ReactNode;
}

export function RetroPanel({ title, aside, children }: PropsWithChildren<RetroPanelProps>) {
  return (
    <section className="retro-panel">
      <div className="retro-panel__header">
        <div className="retro-panel__title">{title}</div>
        {aside}
      </div>
      <div className="retro-panel__body">{children}</div>
    </section>
  );
}
