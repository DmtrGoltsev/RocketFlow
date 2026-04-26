interface ConflictStateProps {
  title: string;
  description: string;
}

export function ConflictState({ title, description }: ConflictStateProps) {
  return (
    <div className="state-box state-box--conflict">
      <div className="state-box__title">{title}</div>
      <div className="muted">{description}</div>
    </div>
  );
}
