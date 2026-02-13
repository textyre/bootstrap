import { BARCODE } from '../../config/constants';
import { TIMINGS } from '../../config/timings';
import { CSS_CLASSES } from '../../config/selectors';
import { logError } from '../../utils/logger';
import { randomString } from '../../utils/random';
import { renderPDF417 } from './barcode.renderer';
import { DOMAdapter } from '../../adapters/DOM.adapter';

/**
 * Creates a fingerprint barcode element with canvas + text overlay.
 * After construction, `container` is ready for DOM insertion.
 * Call `scramble()` to animate random frames before settling on the real fingerprint.
 */
export class FingerprintBarcode {
  private readonly adapter = new DOMAdapter();
  readonly container: HTMLElement;
  private readonly canvas: HTMLCanvasElement;
  private readonly textEl: HTMLElement;

  constructor(private readonly fingerprint: string) {
    this.container = this.adapter.createElement('span');
    this.container.className = CSS_CLASSES.FP_CONTAINER;

    this.canvas = this.adapter.createElement('canvas');
    this.canvas.classList.add(CSS_CLASSES.FP_BARCODE);

    this.textEl = this.adapter.createElement('span');
    this.textEl.className = CSS_CLASSES.FP_TEXT;
    this.textEl.textContent = this.fingerprint;

    this.container.appendChild(this.canvas);
    this.container.appendChild(this.textEl);

    this.renderInitial();
  }

  async scramble(): Promise<void> {
    return new Promise((resolve) => {
      let frame = 0;
      const interval = setInterval(() => {
        frame++;
        if (frame < TIMINGS.FINGERPRINT.SCRAMBLE_FRAMES) {
          this.renderToCanvas(randomString(this.fingerprint.length));
        } else {
          clearInterval(interval);
          this.renderToCanvas(this.fingerprint);
          resolve();
        }
      }, TIMINGS.FINGERPRINT.SCRAMBLE_INTERVAL);
    });
  }

  private renderInitial(): void {
    this.renderToCanvas(randomString(this.fingerprint.length));
  }

  private renderToCanvas(text: string): void {
    try {
      const tmp = this.adapter.createElement('canvas');
      renderPDF417(tmp, BARCODE.FINGERPRINT, text);

      const ratio = BARCODE.FP_HEIGHT / tmp.height;
      this.canvas.width = Math.round(tmp.width * ratio);
      this.canvas.height = BARCODE.FP_HEIGHT;

      const ctx = this.canvas.getContext('2d');
      if (ctx) {
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(tmp, 0, 0, this.canvas.width, this.canvas.height);
      }
    } catch (err) {
      logError('barcode:fingerprint', err);
    }
  }
}
