import { Link } from 'react-router-dom';

import { RetroButton } from '../primitives/RetroButton';
import { RetroPanel } from '../primitives/RetroPanel';

interface LockedStateProps {
  locale: 'ru' | 'en';
}

export function LockedState({ locale }: LockedStateProps) {
  return (
    <RetroPanel title={locale === 'ru' ? 'Защищенная граница' : 'Protected boundary'}>
      <div className="stack">
        <div className="surface-title">
          {locale === 'ru' ? 'Рабочая зона пока закрыта для режима гостя' : 'Workspace is locked in guest mode'}
        </div>
        <div className="surface-subtitle">
          {locale === 'ru'
            ? 'Это демонстрационный guard для shell foundation. В status bar можно переключиться в режим участника до подключения полноценной auth/session логики.'
            : 'This is a shell-foundation guard. Use the status bar to switch into member mode until the real auth/session flow lands.'}
        </div>
        <div className="cluster">
          <RetroButton as={Link} to="/" variant="primary">
            {locale === 'ru' ? 'Вернуться на старт' : 'Return to start'}
          </RetroButton>
          <RetroButton as={Link} to="/auth/login" variant="ghost">
            {locale === 'ru' ? 'Открыть границу входа' : 'Open login boundary'}
          </RetroButton>
        </div>
      </div>
    </RetroPanel>
  );
}
