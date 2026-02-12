import { BARCODE } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import { logError } from '../../utils/logger';
import { renderPDF417 } from './barcode.renderer';

export function renderUsernameBarcode(username: string): void {
  const el = document.querySelector(SELECTORS.USERNAME_BARCODE) as HTMLCanvasElement | null;
  if (!el) return;

  try {
    renderPDF417(el, BARCODE.USERNAME, username.toUpperCase());
  } catch (err) {
    logError('barcode:username', err);
  }
}
