import { BARCODE, HASH } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import type { SecurityData } from '../../types/barcode.types';
import { hashBytes, toHex } from './hash';
import { renderPDF417 } from './barcode.renderer';

export type { SecurityData };

export function renderSecurityBarcode(data: SecurityData): void {
  const canvas = document.getElementById(SELECTORS.SECURITY_MATRIX) as HTMLCanvasElement | null;
  const uuidEl = document.getElementById(SELECTORS.SECURITY_UUID);
  const coordsEl = document.getElementById(SELECTORS.SECURITY_COORDS);

  if (!canvas) return;

  const identity = `${data.hostname}:${data.username}:${data.ip}:${data.kernel}`;
  const bytes = hashBytes(identity);
  const sig = toHex(bytes, HASH.SIG_BYTES);

  try {
    renderPDF417(canvas, BARCODE.SECURITY, identity);
  } catch {
    // Barcode generation failed — leave empty
  }

  if (uuidEl) uuidEl.textContent = `SIG:${sig}`;
  if (coordsEl) coordsEl.textContent = data.hostname.toUpperCase();
}
