import { CalendarDays, ListTree, LogOut, Settings, Share2, UserCircle } from 'lucide-react';
import { useState } from 'react';
import { NavLink } from 'react-router-dom';

import { routeInventory } from '../../app/route-map';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';
import { useAuth } from '../../features/auth';
import { LanguageSwitch } from './StatusBar';

const navIcons = {
  tasks: ListTree,
  calendar: CalendarDays,
  sharing: Share2,
  settings: Settings,
};

export function SidebarNav() {
  const { copy, locale } = useAppRuntime();
  const { logout } = useAuth();
  const [profileOpen, setProfileOpen] = useState(false);
  const navRoutes = routeInventory.filter((route) => route.nav && route.id !== 'settings');
  const settingsRoute = routeInventory.find((route) => route.id === 'settings');
  const profileLabel = locale === 'ru' ? 'Профиль' : 'Profile';

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
        <div className="rail-profile">
          <button
            type="button"
            className="rail__item"
            aria-label={profileLabel}
            title={profileLabel}
            aria-haspopup="menu"
            aria-expanded={profileOpen}
            onClick={() => setProfileOpen((current) => !current)}
          >
            <UserCircle aria-hidden="true" size={21} strokeWidth={1.75} />
          </button>
          {profileOpen ? (
            <div className="rail-profile__menu" role="menu">
              {settingsRoute ? (
                <NavLink
                  className="rail-profile__item"
                  to={settingsRoute.path}
                  role="menuitem"
                  onClick={() => setProfileOpen(false)}
                >
                  <Settings aria-hidden="true" size={16} strokeWidth={1.75} />
                  <span>{settingsRoute.label[locale]}</span>
                </NavLink>
              ) : null}
              <button className="rail-profile__item" type="button" role="menuitem" onClick={() => void logout()}>
                <LogOut aria-hidden="true" size={16} strokeWidth={1.75} />
                <span>{copy('signOut')}</span>
              </button>
            </div>
          ) : null}
        </div>
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
