import { SELECTORS } from './config/selectors';
import type { IGreeterConfigAdapter } from './adapters/greeter-config.adapter';
import { createGreeterConfigAdapter } from './adapters/greeter-config.adapter';
import { logError } from './utils/logger';

export function initBackground(adapter?: IGreeterConfigAdapter): void {
  const bgEl = document.querySelector(SELECTORS.BACKGROUND) as HTMLElement | null;
  if (!bgEl) return;

  const config = adapter ?? createGreeterConfigAdapter();

  try {
    const bgDir = config.getBackgroundImagesDir();
    if (!bgDir) return;

    config.listImages(bgDir, (images: string[]) => {
      if (images.length > 0) {
        bgEl.style.backgroundImage = `url('${images[0]}')`;
      }
    });
  } catch (err) {
    logError('background:load', err);
  }
}
