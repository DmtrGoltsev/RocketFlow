import { createBrowserRouter } from 'react-router-dom';

import { CalendarRoute, SettingsRoute, SharingRoute } from '../features/advanced';
import { LoginRoute, LogoutRoute, RegisterRoute } from '../features/auth';
import { FoldersRoute, GoalsRoute, TasksRoute } from '../features/planning';
import { ProtectedBoundary } from './guards/ProtectedBoundary';
import { ProtectedLayout } from './layouts/ProtectedLayout';
import { PublicLayout } from './layouts/PublicLayout';
import { HomeRoute } from './routes/HomeRoute';
import { NotFoundRoute } from './routes/NotFoundRoute';
import { RoutePlaceholder } from './routes/RoutePlaceholder';

export const appRouter = createBrowserRouter([
  {
    element: <PublicLayout />,
    children: [
      {
        path: '/',
        element: <HomeRoute />
      },
      {
        path: '/auth/login',
        element: <LoginRoute />
      },
      {
        path: '/auth/register',
        element: <RegisterRoute />
      },
      {
        path: '/auth/logout',
        element: <LogoutRoute />
      }
    ]
  },
  {
    path: '/app',
    element: (
      <ProtectedBoundary>
        <ProtectedLayout />
      </ProtectedBoundary>
    ),
    children: [
      {
        index: true,
        element: <RoutePlaceholder routeId="overview" />
      },
      {
        path: 'folders',
        element: <FoldersRoute />
      },
      {
        path: 'goals',
        element: <GoalsRoute />
      },
      {
        path: 'tasks',
        element: <TasksRoute />
      },
      {
        path: 'calendar',
        element: <CalendarRoute />
      },
      {
        path: 'sharing',
        element: <SharingRoute />
      },
      {
        path: 'settings',
        element: <SettingsRoute />
      }
    ]
  },
  {
    path: '*',
    element: <NotFoundRoute />
  }
]);
