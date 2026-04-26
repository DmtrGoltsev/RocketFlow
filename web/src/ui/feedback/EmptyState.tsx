interface EmptyStateProps {
  title: string;
  description: string;
}

export function EmptyState({ title, description }: EmptyStateProps) {
  return (
    <div className="state-box state-box--empty">
      <div className="state-box__title">{title}</div>
      <div className="muted">{description}</div>
    </div>
  );
}
