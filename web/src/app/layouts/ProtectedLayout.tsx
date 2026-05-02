import { Outlet } from 'react-router-dom';

import { SidebarNav } from '../../ui/layout/SidebarNav';

export function ProtectedLayout() {
  return (
    <div className="workspace-shell">
      <SidebarNav />
      <main className="workspace-main" aria-live="polite">
        <Outlet />
      </main>
    </div>
  );
}
