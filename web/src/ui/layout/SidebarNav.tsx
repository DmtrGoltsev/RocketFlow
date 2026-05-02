import { ListTree } from 'lucide-react';
import { NavLink } from 'react-router-dom';

import { routeInventory } from '../../app/route-map';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';
import { LanguageSwitch, LogoutButton } from './StatusBar';

export function SidebarNav() {
  const { copy, locale } = useAppRuntime();
  const navRoutes = routeInventory.filter((route) => route.nav);

  return (
    <nav className="rail" aria-label={copy('navigationAria')}>
      <NavLink className="rail__brand" to="/app" aria-label="RocketFlow" title="RocketFlow">
        RF
      </NavLink>

      <div className="rail__primary">
        {navRoutes.map((route) => (
          <NavLink
            key={route.id}
            className="rail__item"
            to={route.path}
            end={route.path === '/app/tasks'}
            aria-label={route.label[locale]}
            title={route.label[locale]}
          >
            <ListTree aria-hidden="true" size={20} strokeWidth={1.75} />
          </NavLink>
        ))}
      </div>

      <div className="rail__bottom">
        <LanguageSwitch compact />
        <LogoutButton />
      </div>
    </nav>
  );
}
