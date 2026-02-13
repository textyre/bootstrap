import { BARCODE } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import { logError } from '../../utils/logger';
import { renderPDF417 } from './barcode.renderer';

export async function renderUsernameBarcode(username: string): Promise<void> {
  const el = document.querySelector(SELECTORS.USERNAME_BARCODE) as HTMLCanvasElement | null;
  if (!el) return;

  try {
    await renderPDF417(el, BARCODE.USERNAME, username.toUpperCase());
  } catch (err) {
    logError('barcode:username', err);
  }
}
