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

interface PlanningHierarchyRowProps {
  active: boolean;
  depth: 0 | 1 | 2;
  title: string;
  meta?: ReactNode;
  marker?: ReactNode;
  onClick: () => void;
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

export function PlanningHierarchyRow({
  active,
  depth,
  title,
  meta,
  marker,
  onClick,
}: PlanningHierarchyRowProps) {
  return (
    <button
      type="button"
      className={`planning-tree-row planning-tree-row--depth-${depth}${active ? ' planning-tree-row--active' : ''}`}
      onClick={onClick}
    >
      <span className="planning-tree-row__rail" aria-hidden="true" />
      <span className="planning-tree-row__marker" aria-hidden="true">
        {marker}
      </span>
      <span className="planning-tree-row__main">
        <span className="planning-tree-row__title">{title}</span>
        {meta ? <span className="planning-tree-row__meta">{meta}</span> : null}
      </span>
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
