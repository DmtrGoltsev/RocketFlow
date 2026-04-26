import { RouterProvider } from 'react-router-dom';

import { AuthProvider } from '../features/auth';
import { I18nProvider } from '../i18n';
import { AppRuntimeProvider } from './foundation/runtime/AppRuntimeContext';
import { appRouter } from './router';

export function App() {
  return (
    <I18nProvider>
      <AuthProvider>
        <AppRuntimeProvider>
          <div className="app-root">
            <RouterProvider router={appRouter} />
          </div>
        </AppRuntimeProvider>
      </AuthProvider>
    </I18nProvider>
  );
}
