import { Link } from 'react-router-dom';

import { ConflictState } from '../../ui/feedback/ConflictState';
import { EmptyState } from '../../ui/feedback/EmptyState';
import { ErrorState } from '../../ui/feedback/ErrorState';
import { LoadingState } from '../../ui/feedback/LoadingState';
import { RetroBadge } from '../../ui/primitives/RetroBadge';
import { RetroButton } from '../../ui/primitives/RetroButton';
import { RetroDialogFrame } from '../../ui/primitives/RetroDialogFrame';
import { RetroField } from '../../ui/primitives/RetroField';
import { RetroList } from '../../ui/primitives/RetroList';
import { RetroPanel } from '../../ui/primitives/RetroPanel';
import { routeInventory } from '../route-map';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

export function HomeRoute() {
  const { locale, sessionMode } = useAppRuntime();
  const publicRoutes = routeInventory.filter((route) => route.audience === 'public');
  const protectedRoutes = routeInventory.filter((route) => route.audience === 'protected');

  return (
    <div className="stack">
      <RetroPanel
        title={locale === 'ru' ? 'Назначение' : 'Purpose'}
        aside={<RetroBadge tone="info">Wave A</RetroBadge>}
      >
        <div className="stack stack--tight">
          <div className="surface-title">
            {locale === 'ru'
              ? 'Каркас SPA с ретро-навигацией и устойчивыми границами модулей'
              : 'SPA shell with retro navigation and stable module boundaries'}
          </div>
          <div className="surface-subtitle">
            {locale === 'ru'
              ? 'Эта площадка готовит публичную и защищенную части приложения для следующих волн: auth, planning, calendar, sharing и settings.'
              : 'This foundation prepares the public and protected application areas for the next auth, planning, calendar, sharing, and settings waves.'}
          </div>
          <div className="cluster">
            <RetroButton as={Link} to="/app" variant="primary">
              {locale === 'ru' ? 'Открыть рабочую зону' : 'Open workspace'}
            </RetroButton>
            <RetroButton as={Link} to="/auth/login" variant="secondary">
              {locale === 'ru' ? 'Граница входа' : 'Login boundary'}
            </RetroButton>
            <RetroBadge tone={sessionMode === 'member' ? 'success' : 'warning'}>
              {locale === 'ru'
                ? `Режим превью: ${sessionMode === 'member' ? 'участник' : 'гость'}`
                : `Preview mode: ${sessionMode === 'member' ? 'member' : 'guest'}`}
            </RetroBadge>
          </div>
        </div>
      </RetroPanel>

      <div className="shell-grid shell-grid--2">
        <RetroPanel title={locale === 'ru' ? 'Публичные поверхности' : 'Public surfaces'}>
          <div className="inventory-grid">
            {publicRoutes.map((route) => (
              <div key={route.id} className="inventory-card">
                <div className="inventory-card__label">{route.label[locale]}</div>
                <div className="inventory-card__path">{route.path}</div>
                <p className="inventory-card__summary">{route.summary[locale]}</p>
              </div>
            ))}
          </div>
        </RetroPanel>

        <RetroPanel title={locale === 'ru' ? 'Защищенные поверхности' : 'Protected surfaces'}>
          <div className="inventory-grid">
            {protectedRoutes.map((route) => (
              <div key={route.id} className="inventory-card">
                <div className="inventory-card__label">{route.label[locale]}</div>
                <div className="inventory-card__path">{route.path}</div>
                <p className="inventory-card__summary">{route.summary[locale]}</p>
              </div>
            ))}
          </div>
        </RetroPanel>
      </div>

      <div className="shell-grid shell-grid--2">
        <RetroPanel title={locale === 'ru' ? 'Базовые примитивы' : 'Base primitives'}>
          <div className="stack">
            <div className="cluster">
              <RetroButton variant="primary">{locale === 'ru' ? 'Основная' : 'Primary'}</RetroButton>
              <RetroButton variant="secondary">{locale === 'ru' ? 'Вторичная' : 'Secondary'}</RetroButton>
              <RetroButton variant="ghost" size="small">
                {locale === 'ru' ? 'Малая' : 'Small'}
              </RetroButton>
              <RetroBadge tone="success">{locale === 'ru' ? 'Готово' : 'Ready'}</RetroBadge>
              <RetroBadge tone="warning">{locale === 'ru' ? 'Ожидает' : 'Pending'}</RetroBadge>
              <RetroBadge tone="danger">{locale === 'ru' ? 'Риск' : 'Risk'}</RetroBadge>
            </div>
            <RetroField
              label={locale === 'ru' ? 'Текстовое поле' : 'Text field'}
              hint={
                locale === 'ru'
                  ? 'Поле и подписи готовы для будущего form composition.'
                  : 'Field and captions are ready for later form composition.'
              }
            >
              <input
                className="retro-input"
                defaultValue={locale === 'ru' ? 'Ретро-контрол' : 'Retro control'}
              />
            </RetroField>
            <RetroList
              items={[
                {
                  title: locale === 'ru' ? 'Панель' : 'Panel',
                  body:
                    locale === 'ru'
                      ? 'Секции с заголовком для плотных экранов.'
                      : 'Sectioned container for dense screens.'
                },
                {
                  title: locale === 'ru' ? 'Список' : 'List',
                  body:
                    locale === 'ru'
                      ? 'Повторяемый формат для inbox, folders и task groups.'
                      : 'Repeatable format for inbox, folders, and task groups.'
                },
                {
                  title: locale === 'ru' ? 'Диалог' : 'Dialog',
                  body:
                    locale === 'ru'
                      ? 'Рамка для будущих share/settings modals.'
                      : 'Framed shell for later share/settings modals.'
                }
              ]}
            />
          </div>
        </RetroPanel>

        <RetroDialogFrame
          title={locale === 'ru' ? 'Диалоговый каркас' : 'Dialog scaffold'}
          footer={
            <div className="cluster">
              <RetroButton variant="ghost">{locale === 'ru' ? 'Отмена' : 'Cancel'}</RetroButton>
              <RetroButton variant="primary">{locale === 'ru' ? 'Сохранить' : 'Save'}</RetroButton>
            </div>
          }
        >
          <div className="stack stack--tight">
            <div className="surface-subtitle">
              {locale === 'ru'
                ? 'Используйте эту рамку для будущих диалогов доступа, конфликтов и подтверждений.'
                : 'Use this frame for future share, conflict, and confirmation dialogs.'}
            </div>
            <div className="spacer-line" />
            <div className="caps">{locale === 'ru' ? 'Стабильный shell boundary' : 'Stable shell boundary'}</div>
          </div>
        </RetroDialogFrame>
      </div>

      <RetroPanel title={locale === 'ru' ? 'Глобальные UX-состояния' : 'Global UX states'}>
        <div className="shell-grid shell-grid--2">
          <LoadingState
            title={locale === 'ru' ? 'Загрузка данных' : 'Loading data'}
            description={
              locale === 'ru'
                ? 'Подходит для первичной загрузки shell и route bootstrap.'
                : 'Fits initial shell loading and route bootstrap.'
            }
          />
          <EmptyState
            title={locale === 'ru' ? 'Пустая поверхность' : 'Empty surface'}
            description={
              locale === 'ru'
                ? 'Основа для empty states у folders, goals и invitations.'
                : 'Foundation for folders, goals, and invitations empty states.'
            }
          />
          <ErrorState
            title={locale === 'ru' ? 'Ошибка загрузки' : 'Load error'}
            description={
              locale === 'ru'
                ? 'Стандартный контейнер для traceId и retry-кнопки.'
                : 'Standard container for traceId and retry actions.'
            }
          />
          <ConflictState
            title={locale === 'ru' ? 'Конфликт версии' : 'Version conflict'}
            description={
              locale === 'ru'
                ? 'Подготовлено для planning optimistic locking через version.'
                : 'Prepared for planning optimistic locking via version.'
            }
          />
        </div>
      </RetroPanel>
    </div>
  );
}
