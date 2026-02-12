import { TIMING, BARCODE } from '../../config/constants';
import { CSS_CLASSES } from '../../config/selectors';
import { randomString } from '../../utils/random';
import { renderPDF417 } from './barcode.renderer';

function renderToCanvas(canvas: HTMLCanvasElement, text: string): void {
  try {
    const tmp = document.createElement('canvas');
    renderPDF417(tmp, BARCODE.FINGERPRINT, text);

    const ratio = BARCODE.FP_HEIGHT / tmp.height;
    canvas.width = Math.round(tmp.width * ratio);
    canvas.height = BARCODE.FP_HEIGHT;

    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(tmp, 0, 0, canvas.width, canvas.height);
    }
  } catch {
    // ignore
  }
}

export function renderFingerprintBarcode(fingerprint: string): {
  container: HTMLElement;
  scramble: () => Promise<void>;
} {
  const container = document.createElement('span');
  container.className = CSS_CLASSES.FP_CONTAINER;

  const canvas = document.createElement('canvas');
  canvas.classList.add(CSS_CLASSES.FP_BARCODE);

  renderToCanvas(canvas, randomString(fingerprint.length));

  const textEl = document.createElement('span');
  textEl.className = CSS_CLASSES.FP_TEXT;
  textEl.textContent = fingerprint;

  container.appendChild(canvas);
  container.appendChild(textEl);

  const scramble = (): Promise<void> =>
    new Promise((resolve) => {
      let frame = 0;
      const interval = setInterval(() => {
        frame++;
        if (frame < TIMING.SCRAMBLE_FRAMES) {
          renderToCanvas(canvas, randomString(fingerprint.length));
        } else {
          clearInterval(interval);
          renderToCanvas(canvas, fingerprint);
          resolve();
        }
      }, TIMING.SCRAMBLE_INTERVAL);
    });

  return { container, scramble };
}
