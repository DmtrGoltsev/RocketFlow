import type { ComponentPropsWithoutRef, ElementType, ReactNode } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';
type ButtonSize = 'default' | 'small';

interface RetroButtonOwnProps<TElement extends ElementType> {
  as?: TElement;
  children: ReactNode;
  variant?: ButtonVariant;
  size?: ButtonSize;
}

type RetroButtonProps<TElement extends ElementType> = RetroButtonOwnProps<TElement> &
  Omit<ComponentPropsWithoutRef<TElement>, keyof RetroButtonOwnProps<TElement>>;

export function RetroButton<TElement extends ElementType = 'button'>({
  as,
  children,
  variant = 'secondary',
  size = 'default',
  ...restProps
}: RetroButtonProps<TElement>) {
  const Component = as ?? 'button';
  const className = [
    'retro-button',
    variant !== 'secondary' ? `retro-button--${variant}` : '',
    size === 'small' ? 'retro-button--small' : '',
    'className' in restProps && typeof restProps.className === 'string' ? restProps.className : ''
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <Component
      {...restProps}
      className={className}
    >
      {children}
    </Component>
  );
}
