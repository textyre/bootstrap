import { SELECTORS } from './config/selectors';
import type { IGreeterConfigAdapter } from './adapters/greeter-config.adapter';
import { createGreeterConfigAdapter } from './adapters/greeter-config.adapter';

export function initBackground(adapter?: IGreeterConfigAdapter): void {
  const bgEl = document.getElementById(SELECTORS.BACKGROUND);
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
  } catch {
    // greeter API not available — CSS background is fine
  }
}
