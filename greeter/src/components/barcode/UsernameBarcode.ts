import { BARCODE } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import { Barcode } from './Barcode';

export class UsernameBarcode extends Barcode {
  protected readonly config = BARCODE.USERNAME as Record<string, unknown>;
  protected readonly logTag = 'barcode:username';

  async render(username: string): Promise<void> {
    const canvas = document.querySelector(SELECTORS.USERNAME_BARCODE) as HTMLCanvasElement | null;
    if (!canvas) return;
    await this.renderToCanvas(canvas, username.toUpperCase());
  }
}
