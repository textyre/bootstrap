import { TIMING } from '../../config/constants';
import { CSS_CLASSES } from '../../config/selectors';

/**
 * Types text character-by-character into a container element with a blinking cursor.
 * Call `type()` to start; the returned promise resolves when all characters have been typed.
 */
export class Typewriter {
  private charIdx = 0;
  private readonly cursor: HTMLElement;

  constructor(
    private readonly container: HTMLElement,
    private readonly text: string,
  ) {
    this.cursor = document.createElement('span');
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
      }, TIMING.CHAR_DELAY);
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
