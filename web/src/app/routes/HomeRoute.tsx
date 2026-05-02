import { Link } from 'react-router-dom';
import { Circle, Folder, SquareCheck, Target } from 'lucide-react';

import { useAuth } from '../../features/auth';
import { useI18n } from '../../i18n';

export function HomeRoute() {
  const { t, locale } = useI18n();
  const { status } = useAuth();
  const isAuthenticated = status === 'authenticated';

  return (
    <div className="entry-layout">
      <section className="entry-copy-block">
        <div className="wordmark">RocketFlow</div>
        <h1 className="entry-title">{t('home.heading')}</h1>
        <p className="entry-copy">{t('home.body')}</p>
        <div className="entry-actions">
          <Link className="button button--primary" to={isAuthenticated ? '/app' : '/auth/login'}>
            {isAuthenticated ? t('home.openWorkspace') : t('home.openLogin')}
          </Link>
          {!isAuthenticated ? (
            <Link className="button button--ghost" to="/auth/register">
              {t('home.openRegister')}
            </Link>
          ) : null}
        </div>
      </section>

      <section className="entry-preview" aria-label="RocketFlow">
        <div className="entry-preview__mark">RF</div>
        <div className="entry-preview__rows">
          <div className="entry-preview__row">
            <Folder size={18} strokeWidth={1.75} />
            <span>{locale === 'ru' ? 'Запуск продукта' : 'Product launch'}</span>
          </div>
          <div className="entry-preview__row entry-preview__row--indent">
            <Target size={18} strokeWidth={1.75} />
            <span>{locale === 'ru' ? 'Мягкий релиз' : 'Soft release'}</span>
          </div>
          <div className="entry-preview__row entry-preview__row--deep">
            <Circle size={16} strokeWidth={1.75} />
            <span>{locale === 'ru' ? 'Подготовить страницу входа' : 'Prepare the sign-in screen'}</span>
          </div>
          <div className="entry-preview__row entry-preview__row--deep">
            <SquareCheck size={16} strokeWidth={1.75} />
            <span>{locale === 'ru' ? 'Созвон с командой' : 'Team call'}</span>
          </div>
        </div>
      </section>
    </div>
  );
}
