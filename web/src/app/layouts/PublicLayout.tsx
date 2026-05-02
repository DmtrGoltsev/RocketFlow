import { Outlet } from 'react-router-dom';

import { LanguageSwitch } from '../../ui/layout/StatusBar';

export function PublicLayout() {
  return (
    <div className="public-shell">
      <header className="public-shell__top">
        <div className="public-brand" aria-label="RocketFlow">
          <span className="public-brand__mark">RF</span>
          <span className="public-brand__name">RocketFlow</span>
        </div>
        <LanguageSwitch />
      </header>
      <main className="public-shell__main">
        <Outlet />
      </main>
    </div>
  );
}
