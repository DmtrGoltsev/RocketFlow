import { Link } from 'react-router-dom';

import { RetroButton } from '../../ui/primitives/RetroButton';
import { RetroPanel } from '../../ui/primitives/RetroPanel';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

export function NotFoundRoute() {
  const { locale } = useAppRuntime();

  return (
    <div className="shell-page shell-page--public">
      <div className="hero-grid">
        <RetroPanel title="404">
          <div className="stack">
            <div className="surface-title">
              {locale === 'ru' ? 'Страница не найдена' : 'Page not found'}
            </div>
            <div className="surface-subtitle">
              {locale === 'ru'
                ? 'Проверьте адрес или вернитесь в RocketFlow.'
                : 'Check the address or return to RocketFlow.'}
            </div>
            <div className="cluster">
              <RetroButton as={Link} to="/" variant="primary">
                {locale === 'ru' ? 'На главную' : 'Home'}
              </RetroButton>
              <RetroButton as={Link} to="/app" variant="ghost">
                {locale === 'ru' ? 'К задачам' : 'Tasks'}
              </RetroButton>
            </div>
          </div>
        </RetroPanel>
      </div>
    </div>
  );
}
