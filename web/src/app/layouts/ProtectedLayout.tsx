import { Outlet, useLocation } from 'react-router-dom';

import { AppHeader } from '../../ui/layout/AppHeader';
import { SidebarNav } from '../../ui/layout/SidebarNav';
import { StatusBar } from '../../ui/layout/StatusBar';
import { getRouteById, routeInventory } from '../route-map';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

function resolveCurrentRoute(pathname: string) {
  const directMatch = routeInventory.find((route) => route.path === pathname);

  if (directMatch) {
    return directMatch;
  }

  if (pathname.startsWith('/app')) {
    return getRouteById('overview');
  }

  return undefined;
}

export function ProtectedLayout() {
  const location = useLocation();
  const { locale, copy } = useAppRuntime();
  const currentRoute = resolveCurrentRoute(location.pathname);

  return (
    <div className="shell-page">
      <div className="workspace-shell">
        <aside className="workspace-sidebar">
          <SidebarNav />
        </aside>
        <div className="workspace-main">
          <div className="retro-window__titlebar">
            <div>
              <div className="caps">{copy('protectedLabel')}</div>
              <div className="retro-window__title">
                {currentRoute ? currentRoute.label[locale] : copy('brand')}
              </div>
            </div>
            <div className="retro-window__meta">
              <span>{currentRoute?.path ?? '/app'}</span>
              <div className="window-controls" aria-hidden="true">
                <span />
                <span />
                <span />
              </div>
            </div>
          </div>
          <div className="retro-window__body stack">
            <AppHeader
              eyebrow={copy('brand')}
              title={currentRoute ? currentRoute.label[locale] : copy('overview')}
              subtitle={currentRoute ? currentRoute.summary[locale] : copy('tagline')}
              chromeText="Desktop / Protected Workspace"
            />
            <Outlet />
          </div>
          <StatusBar />
        </div>
      </div>
    </div>
  );
}
