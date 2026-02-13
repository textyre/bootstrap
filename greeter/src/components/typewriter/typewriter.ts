import { TIMINGS } from './../../config/timings';
import { CSS_CLASSES } from '../../config/selectors';
import { DOMAdapter } from '../../adapters/DOM.adapter';

/**
 * Types text character-by-character into a container element with a blinking cursor.
 * Call `type()` to start; the returned promise resolves when all characters have been typed.
 */
export class Typewriter {
  private readonly adapter = new DOMAdapter();
  private charIdx = 0;
  private readonly cursor: HTMLElement;

  constructor(
    private readonly container: HTMLElement,
    private readonly text: string,
  ) {
    this.cursor = this.adapter.createElement('span');
    this.cursor.className = CSS_CLASSES.LOG_CURSOR;
    this.container.appendChild(this.cursor);
  }

  async type(): Promise<void> {
    return new Promise((resolve) => {
      const intervalId = setInterval(() => {
        if (this.charIdx < this.text.length) {
          this.appendChar();
        } else {
          clearInterval(intervalId);
          this.removeCursor();
          resolve();
        }
      }, TIMINGS.TYPEWRITER.CHAR_DELAY);
    });
  }

  private appendChar(): void {
    this.container.insertBefore(
      document.createTextNode(this.text[this.charIdx++]),
      this.cursor,
    );
  }

  private removeCursor(): void {
    this.cursor.remove();
  }
}
