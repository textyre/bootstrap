import { BARCODE } from '../../config/constants';
import { TIMINGS } from '../../config/timings';
import { CSS_CLASSES } from '../../config/selectors';
import { randomString } from '../../utils/random';
import { DOMAdapter } from '../../adapters/DOM.adapter';
import { Barcode } from './Barcode';

export class FingerprintBarcode extends Barcode {
  protected readonly config = BARCODE.FINGERPRINT as Record<string, unknown>;
  protected readonly logTag = 'barcode:fingerprint';

  private readonly adapter = new DOMAdapter();
  readonly container: HTMLElement;
  private readonly canvas: HTMLCanvasElement;
  private readonly textEl: HTMLElement;

  constructor(private readonly fingerprint: string) {
    super();

    this.container = this.adapter.createElement('span');
    this.container.className = CSS_CLASSES.FP_CONTAINER;

    this.canvas = this.adapter.createElement('canvas');
    this.canvas.classList.add(CSS_CLASSES.FP_BARCODE);

    this.textEl = this.adapter.createElement('span');
    this.textEl.className = CSS_CLASSES.FP_TEXT;
    this.textEl.textContent = this.fingerprint;

    this.container.appendChild(this.canvas);
    this.container.appendChild(this.textEl);

    this.renderScaled(randomString(this.fingerprint.length));
  }

  async scramble(): Promise<void> {
    for (let frame = 0; frame < TIMINGS.FINGERPRINT.SCRAMBLE_FRAMES; frame++) {
      await this.renderScaled(randomString(this.fingerprint.length));
      await new Promise((r) => setTimeout(r, TIMINGS.FINGERPRINT.SCRAMBLE_INTERVAL));
    }
    await this.renderScaled(this.fingerprint);
  }

  private async renderScaled(text: string): Promise<void> {
    const tmp = this.adapter.createElement('canvas');
    await this.renderToCanvas(tmp, text);

    const ratio = BARCODE.FP_HEIGHT / tmp.height;
    this.canvas.width = Math.round(tmp.width * ratio);
    this.canvas.height = BARCODE.FP_HEIGHT;

    const ctx = this.canvas.getContext('2d');
    if (ctx) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(tmp, 0, 0, this.canvas.width, this.canvas.height);
    }
  }
}
