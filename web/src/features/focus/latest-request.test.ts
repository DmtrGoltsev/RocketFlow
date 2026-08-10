import { describe, expect, it } from 'vitest';

import { LatestRequestController } from './latest-request';

describe('LatestRequestController', () => {
  it('aborts an older reload when a newer reload begins', () => {
    const controller = new LatestRequestController();
    const first = controller.begin();
    const second = controller.begin();

    expect(first.signal.aborted).toBe(true);
    expect(controller.isCurrent(first)).toBe(false);
    expect(controller.isCurrent(second)).toBe(true);
  });

  it('invalidates an in-flight reload before a mutation applies its response', () => {
    const controller = new LatestRequestController();
    const reload = controller.begin();
    controller.invalidate();

    expect(reload.signal.aborted).toBe(true);
    expect(controller.isCurrent(reload)).toBe(false);
  });
});
