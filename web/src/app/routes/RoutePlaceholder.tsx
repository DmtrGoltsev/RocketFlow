import { RetroBadge } from '../../ui/primitives/RetroBadge';
import { RetroPanel } from '../../ui/primitives/RetroPanel';
import { getRouteById, routeInventory } from '../route-map';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

interface RoutePlaceholderProps {
  routeId: string;
}

export function RoutePlaceholder({ routeId }: RoutePlaceholderProps) {
  const { locale } = useAppRuntime();
  const route = getRouteById(routeId);

  if (!route) {
    return null;
  }

  const siblingRoutes = routeInventory.filter(
    (candidate) => candidate.area === route.area && candidate.id !== route.id,
  );

  return (
    <div className="stack">
      <RetroPanel
        title={locale === 'ru' ? 'Маршрут и владение' : 'Route and ownership'}
        aside={<RetroBadge tone="info">{route.owner}</RetroBadge>}
      >
        <div className="stack stack--tight">
          <div className="surface-header">
            <div className="stack stack--tight">
              <div className="surface-title">{route.label[locale]}</div>
              <div className="surface-subtitle">{route.summary[locale]}</div>
            </div>
            <div className="surface-meta">
              <RetroBadge tone={route.audience === 'protected' ? 'warning' : 'success'}>
                {route.audience === 'protected'
                  ? locale === 'ru'
                    ? 'Protected'
                    : 'Protected'
                  : locale === 'ru'
                    ? 'Public'
                    : 'Public'}
              </RetroBadge>
              <RetroBadge tone="info">{route.path}</RetroBadge>
              <RetroBadge tone="warning">{route.readyState}</RetroBadge>
            </div>
          </div>
          <div className="spacer-line" />
          <div className="shell-grid shell-grid--2">
            <div className="stack stack--tight">
              <div className="caps">{locale === 'ru' ? 'Что уже есть' : 'What exists now'}</div>
              <ul className="retro-list">
                <li className="retro-list__item">
                  <strong>{locale === 'ru' ? 'Стабильный путь' : 'Stable path'}</strong>
                  <span className="muted">
                    {locale === 'ru'
                      ? 'Маршрут уже включен в shell и готов для feature implementation.'
                      : 'The route is already mounted in the shell and ready for feature implementation.'}
                  </span>
                </li>
                <li className="retro-list__item">
                  <strong>{locale === 'ru' ? 'Ретро-хром' : 'Retro chrome'}</strong>
                  <span className="muted">
                    {locale === 'ru'
                      ? 'Панели, заголовки, отступы и статусная строка уже единообразны.'
                      : 'Panels, headers, spacing, and the status bar are already consistent.'}
                  </span>
                </li>
                <li className="retro-list__item">
                  <strong>{locale === 'ru' ? 'Место для интеграции' : 'Integration slot'}</strong>
                  <span className="muted">
                    {locale === 'ru'
                      ? 'Следующие волны могут подключать auth, i18n и API без смены layout boundaries.'
                      : 'Later waves can plug in auth, i18n, and APIs without changing layout boundaries.'}
                  </span>
                </li>
              </ul>
            </div>

            <div className="stack stack--tight">
              <div className="caps">{locale === 'ru' ? 'Соседние поверхности' : 'Adjacent surfaces'}</div>
              <div className="inventory-grid">
                {siblingRoutes.length > 0 ? (
                  siblingRoutes.map((sibling) => (
                    <div key={sibling.id} className="inventory-card">
                      <div className="inventory-card__label">{sibling.label[locale]}</div>
                      <div className="inventory-card__path">{sibling.path}</div>
                      <p className="inventory-card__summary">{sibling.summary[locale]}</p>
                    </div>
                  ))
                ) : (
                  <div className="inventory-card">
                    <div className="inventory-card__label">
                      {locale === 'ru' ? 'Нет соседних поверхностей' : 'No adjacent surfaces'}
                    </div>
                    <p className="inventory-card__summary">
                      {locale === 'ru'
                        ? 'Эта зона служит корневой точкой входа для своей группы.'
                        : 'This route acts as the root entry point for its group.'}
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </RetroPanel>
    </div>
  );
}
