import { SELECTORS } from './config/selectors';
import type { IGreeterConfigAdapter } from './adapters/GreeterConfig.adapter';
import { GreeterConfigAdapter } from './adapters/GreeterConfig.adapter';
import { logError } from './utils/logger';

export class BackgroundManager {
  private readonly adapter: IGreeterConfigAdapter;
  private readonly bgEl: HTMLElement | null;

  constructor(adapter?: IGreeterConfigAdapter) {
    this.adapter = adapter ?? new GreeterConfigAdapter();
    this.bgEl = document.querySelector(SELECTORS.BACKGROUND) as HTMLElement | null;
  }

  init(): void {
    if (!this.bgEl) return;

    try {
      const bgDir = this.adapter.getBackgroundImagesDir();
      if (!bgDir) return;

      this.adapter.listImages(bgDir, (images: string[]) => {
        if (images.length > 0 && this.bgEl) {
          this.bgEl.style.backgroundImage = `url('${images[0]}')`;
        }
      });
    } catch (err) {
      logError('background:load', err);
    }
  }
}
