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
              {locale === 'ru' ? 'Маршрут не найден' : 'Route not found'}
            </div>
            <div className="surface-subtitle">
              {locale === 'ru'
                ? 'Каркас уже работает, но этот путь пока не зарегистрирован.'
                : 'The shell is active, but this path is not registered yet.'}
            </div>
            <div className="cluster">
              <RetroButton as={Link} to="/" variant="primary">
                {locale === 'ru' ? 'Вернуться на старт' : 'Back to start'}
              </RetroButton>
              <RetroButton as={Link} to="/app" variant="ghost">
                {locale === 'ru' ? 'Перейти в workspace' : 'Go to workspace'}
              </RetroButton>
            </div>
          </div>
        </RetroPanel>
      </div>
    </div>
  );
}
