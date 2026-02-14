import { BARCODE, SIG_BYTES } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import type { SecurityData } from '../../types/barcode.types';
import { hashBytes, toHex } from '../../utils/hash';
import { Barcode } from './Barcode';

export type { SecurityData };

export class SecurityBarcode extends Barcode {
  protected readonly config = BARCODE.SECURITY as Record<string, unknown>;
  protected readonly logTag = 'barcode:security';

  constructor(private readonly data: SecurityData) {
    super();
  }

  async render(): Promise<void> {
    const canvas = document.querySelector(SELECTORS.SECURITY_MATRIX) as HTMLCanvasElement | null;
    const uuidEl = document.querySelector(SELECTORS.SECURITY_UUID);
    const coordsEl = document.querySelector(SELECTORS.SECURITY_COORDS);

    if (!canvas) return;

    const identity = `${this.data.hostname}:${this.data.username}:${this.data.ip}:${this.data.kernel}`;
    const bytes = await hashBytes(identity);
    const sig = toHex(bytes, SIG_BYTES);

    await this.renderToCanvas(canvas, identity);

    if (uuidEl) uuidEl.textContent = `SIG:${sig}`;
    if (coordsEl) coordsEl.textContent = this.data.hostname.toUpperCase();
  }
}
