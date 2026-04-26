interface ErrorStateProps {
  title: string;
  description: string;
}

export function ErrorState({ title, description }: ErrorStateProps) {
  return (
    <div className="state-box state-box--error">
      <div className="state-box__title">{title}</div>
      <div className="muted">{description}</div>
    </div>
  );
}
