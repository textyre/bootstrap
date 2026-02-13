import { BARCODE, SIG_BYTES } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import type { SecurityData } from '../../types/barcode.types';
import { logError } from '../../utils/logger';
import { hashBytes, toHex } from './hash';
import { renderPDF417 } from './barcode.renderer';

export type { SecurityData };

/**
 * Renders a PDF417 security barcode from system identity data.
 * Queries the DOM for the security canvas and text elements,
 * then hashes the identity string and renders the barcode + signature.
 */
export class SecurityBarcode {
  constructor(private readonly data: SecurityData) {}

  async render(): Promise<void> {
    const canvas = document.querySelector(SELECTORS.SECURITY_MATRIX) as HTMLCanvasElement | null;
    const uuidEl = document.querySelector(SELECTORS.SECURITY_UUID);
    const coordsEl = document.querySelector(SELECTORS.SECURITY_COORDS);

    if (!canvas) return;

    const identity = `${this.data.hostname}:${this.data.username}:${this.data.ip}:${this.data.kernel}`;
    const bytes = await hashBytes(identity);
    const sig = toHex(bytes, SIG_BYTES);

    try {
      await renderPDF417(canvas, BARCODE.SECURITY, identity);
    } catch (err) {
      logError('barcode:security', err);
    }

    if (uuidEl) uuidEl.textContent = `SIG:${sig}`;
    if (coordsEl) coordsEl.textContent = this.data.hostname.toUpperCase();
  }
}
