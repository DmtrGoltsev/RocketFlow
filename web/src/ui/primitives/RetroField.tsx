import type { PropsWithChildren } from 'react';

interface RetroFieldProps {
  label: string;
  hint?: string;
}

export function RetroField({ label, hint, children }: PropsWithChildren<RetroFieldProps>) {
  return (
    <label className="retro-field">
      <span className="retro-field__label">{label}</span>
      {children}
      {hint ? <span className="retro-field__hint">{hint}</span> : null}
    </label>
  );
}
