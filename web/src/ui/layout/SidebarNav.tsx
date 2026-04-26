import { NavLink } from 'react-router-dom';

import { routeInventory } from '../../app/route-map';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';
import { RetroBadge } from '../primitives/RetroBadge';
import { RetroPanel } from '../primitives/RetroPanel';

export function SidebarNav() {
  const { locale } = useAppRuntime();
  const navRoutes = routeInventory.filter((route) => route.nav);

  return (
    <>
      <RetroPanel
        title={locale === 'ru' ? 'Навигация' : 'Navigation'}
        aside={<RetroBadge tone="info">MVP</RetroBadge>}
      >
        <nav className="nav-list" aria-label={locale === 'ru' ? 'Основная навигация' : 'Main navigation'}>
          {navRoutes.map((route) => (
            <NavLink key={route.id} className="nav-link" to={route.path} end={route.path === '/app'}>
              <span className="nav-link__label">{route.label[locale]}</span>
              <span className="nav-link__meta">{route.area}</span>
            </NavLink>
          ))}
        </nav>
      </RetroPanel>

      <RetroPanel title={locale === 'ru' ? 'Границы волн' : 'Wave boundaries'}>
        <div className="stack stack--tight muted">
          <div>{locale === 'ru' ? 'F1: shell, tokens, layouts' : 'F1: shell, tokens, layouts'}</div>
          <div>{locale === 'ru' ? 'F2: auth and i18n wiring' : 'F2: auth and i18n wiring'}</div>
          <div>{locale === 'ru' ? 'Later: planning, calendar, sharing, settings' : 'Later: planning, calendar, sharing, settings'}</div>
        </div>
      </RetroPanel>
    </>
  );
}
