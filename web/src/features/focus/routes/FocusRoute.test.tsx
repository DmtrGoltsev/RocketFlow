import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { FocusAddButton } from './FocusRoute';

describe('Focus add button', () => {
  it('keeps an accessible name and tooltip when its visible label is hidden on mobile', () => {
    const markup = renderToStaticMarkup(<FocusAddButton label="Add task" onClick={() => undefined} />);

    expect(markup).toContain('aria-label="Add task"');
    expect(markup).toContain('title="Add task"');
    expect(markup).toContain('aria-haspopup="dialog"');
  });
});
