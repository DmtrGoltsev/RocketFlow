export interface LatestRequest {
  generation: number;
  signal: AbortSignal;
}

export class LatestRequestController {
  private generation = 0;
  private controller: AbortController | null = null;

  begin(): LatestRequest {
    this.invalidate();
    const controller = new AbortController();
    this.controller = controller;
    return { generation: this.generation, signal: controller.signal };
  }

  invalidate() {
    this.generation += 1;
    this.controller?.abort();
    this.controller = null;
  }

  isCurrent(request: LatestRequest) {
    return request.generation === this.generation && !request.signal.aborted;
  }

  finish(request: LatestRequest) {
    if (this.isCurrent(request)) this.controller = null;
  }
}
