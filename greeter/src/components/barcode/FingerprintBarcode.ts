import { BARCODE } from '../../config/constants';
import { TIMINGS } from '../../config/timings';
import { CSS_CLASSES } from '../../config/selectors';
import { randomString } from '../../utils/random';
import { Scrambler } from '../../utils/Scrambler';
import { CanvasScaler } from '../../utils/CanvasScaler';
import { DOMAdapter } from '../../adapters/DOM.adapter';
import { Barcode } from './Barcode';

export class FingerprintBarcode extends Barcode {
  protected readonly config = BARCODE.FINGERPRINT as Record<string, unknown>;
  protected readonly logTag = 'barcode:fingerprint';

  private readonly adapter = new DOMAdapter();
  private readonly scrambler = new Scrambler(
    TIMINGS.FINGERPRINT.SCRAMBLE_FRAMES,
    TIMINGS.FINGERPRINT.SCRAMBLE_INTERVAL,
  );
  private readonly scaler: CanvasScaler;

  readonly container: HTMLElement;
  private readonly canvas: HTMLCanvasElement;
  private readonly textEl: HTMLElement;

  constructor(private readonly fingerprint: string) {
    super();

    this.container = this.adapter.createElement('span');
    this.container.className = CSS_CLASSES.FP_CONTAINER;

    this.canvas = this.adapter.createElement('canvas');
    this.canvas.classList.add(CSS_CLASSES.FP_BARCODE);
    this.scaler = new CanvasScaler(this.canvas, BARCODE.FP_HEIGHT);

    this.textEl = this.adapter.createElement('span');
    this.textEl.className = CSS_CLASSES.FP_TEXT;
    this.textEl.textContent = this.fingerprint;

    this.container.appendChild(this.canvas);
    this.container.appendChild(this.textEl);

    this.renderScaled(randomString(this.fingerprint.length));
  }

  async scramble(): Promise<void> {
    await this.scrambler.run(this.fingerprint, (text) => this.renderScaled(text));
  }

  private async renderScaled(text: string): Promise<void> {
    const tmp = this.adapter.createElement('canvas');
    await this.renderToCanvas(tmp, text);
    this.scaler.apply(tmp);
  }
}
