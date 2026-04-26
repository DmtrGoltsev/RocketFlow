interface AuthNoticeProps {
  tone?: 'info' | 'error';
  message: string;
  traceId?: string;
}

export function AuthNotice({ tone = 'info', message, traceId }: AuthNoticeProps) {
  return (
    <div className={`state-box ${tone === 'error' ? 'state-box--error' : 'state-box--loading'}`}>
      <div className="state-box__title">{message}</div>
      {traceId ? <div className="muted">traceId: {traceId}</div> : null}
    </div>
  );
}

