import { logError } from '../../utils/logger';

export abstract class Barcode {
  protected abstract readonly config: Record<string, unknown>;
  protected abstract readonly logTag: string;

  protected async renderToCanvas(canvas: HTMLCanvasElement, text: string): Promise<void> {
    try {
      const { default: bwipjs } = await import('bwip-js');
      bwipjs.toCanvas(canvas, { ...this.config, text } as Parameters<typeof bwipjs.toCanvas>[1]);
    } catch (err) {
      logError(this.logTag, err);
    }
  }
}
