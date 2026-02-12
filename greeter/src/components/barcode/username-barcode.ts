import { BARCODE } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import { renderPDF417 } from './barcode.renderer';

export function renderUsernameBarcode(username: string): void {
  const el = document.getElementById(SELECTORS.USERNAME_BARCODE) as HTMLCanvasElement | null;
  if (!el) return;

  try {
    renderPDF417(el, BARCODE.USERNAME, username.toUpperCase());
  } catch {
    // Barcode generation failed — leave empty
  }
}
