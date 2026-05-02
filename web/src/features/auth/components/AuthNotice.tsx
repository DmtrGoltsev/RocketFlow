interface AuthNoticeProps {
  tone?: 'info' | 'error';
  message: string;
}

export function AuthNotice({ tone = 'info', message }: AuthNoticeProps) {
  return (
    <div className={`state-box ${tone === 'error' ? 'state-box--error' : 'state-box--loading'}`}>
      <div className="state-box__title">{message}</div>
    </div>
  );
}
