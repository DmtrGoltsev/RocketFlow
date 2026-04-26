import type { ReactNode } from 'react';

interface PlanningSplitLayoutProps {
  sidebar: ReactNode;
  detail: ReactNode;
}

interface PlanningRecordButtonProps {
  active: boolean;
  title: string;
  subtitle: string;
  meta?: ReactNode;
  onClick: () => void;
}

interface PlanningInlineNoticeProps {
  tone: 'error' | 'warning' | 'info';
  children: ReactNode;
}

interface PlanningMetaListProps {
  items: Array<{
    label: string;
    value: ReactNode;
  }>;
}

export function PlanningSplitLayout({ sidebar, detail }: PlanningSplitLayoutProps) {
  return (
    <div className="planning-grid">
      <div className="planning-grid__sidebar">{sidebar}</div>
      <div className="planning-grid__detail">{detail}</div>
    </div>
  );
}

export function PlanningRecordButton({
  active,
  title,
  subtitle,
  meta,
  onClick,
}: PlanningRecordButtonProps) {
  return (
    <button
      type="button"
      className={`planning-record${active ? ' planning-record--active' : ''}`}
      onClick={onClick}
    >
      <div className="planning-record__title">{title}</div>
      <div className="planning-record__subtitle">{subtitle}</div>
      {meta ? <div className="planning-record__meta">{meta}</div> : null}
    </button>
  );
}

export function PlanningInlineNotice({ tone, children }: PlanningInlineNoticeProps) {
  return <div className={`planning-inline planning-inline--${tone}`}>{children}</div>;
}

export function PlanningMetaList({ items }: PlanningMetaListProps) {
  return (
    <dl className="planning-meta-list">
      {items.map((item) => (
        <div key={item.label} className="planning-meta-list__row">
          <dt>{item.label}</dt>
          <dd>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

export function PlanningFieldError({ message }: { message?: string }) {
  return message ? <div className="planning-field-error">{message}</div> : null;
}

