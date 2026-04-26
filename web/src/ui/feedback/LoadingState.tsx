interface LoadingStateProps {
  title: string;
  description: string;
}

export function LoadingState({ title, description }: LoadingStateProps) {
  return (
    <div className="state-box state-box--loading">
      <div className="state-box__title">{title}</div>
      <div className="muted">{description}</div>
    </div>
  );
}
