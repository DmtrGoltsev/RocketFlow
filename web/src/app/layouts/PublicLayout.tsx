import { Outlet } from 'react-router-dom';

import { AppHeader } from '../../ui/layout/AppHeader';
import { StatusBar } from '../../ui/layout/StatusBar';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

export function PublicLayout() {
  const { copy } = useAppRuntime();

  return (
    <div className="shell-page shell-page--public">
      <div className="hero-grid">
        <div className="retro-window">
          <AppHeader
            eyebrow={copy('publicLabel')}
            title={copy('brand')}
            subtitle={copy('tagline')}
            chromeText="Wave A / Shell Foundation"
          />
          <div className="retro-window__body">
            <Outlet />
          </div>
          <StatusBar />
        </div>
      </div>
    </div>
  );
}
