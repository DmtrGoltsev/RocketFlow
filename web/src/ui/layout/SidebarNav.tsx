import { CalendarDays, ListTree, Settings, Share2 } from 'lucide-react';
import { NavLink } from 'react-router-dom';

import { routeInventory } from '../../app/route-map';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';
import { LanguageSwitch, LogoutButton } from './StatusBar';

const navIcons = {
  tasks: ListTree,
  calendar: CalendarDays,
  sharing: Share2,
  settings: Settings,
};

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
          <NavItem key={route.id} route={route} label={route.label[locale]} />
        ))}
      </div>

      <div className="rail__bottom">
        <LanguageSwitch compact />
        <LogoutButton />
      </div>
    </nav>
  );
}

function NavItem({ route, label }: { route: (typeof routeInventory)[number]; label: string }) {
  const Icon = navIcons[route.id as keyof typeof navIcons] ?? ListTree;

  return (
    <NavLink
      className="rail__item"
      to={route.path}
      end={route.path === '/app/tasks'}
      aria-label={label}
      title={label}
    >
      <Icon aria-hidden="true" size={20} strokeWidth={1.75} />
    </NavLink>
  );
}
