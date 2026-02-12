import { TIMING } from '../../config/constants';
import { CSS_CLASSES } from '../../config/selectors';

/**
 * Type text character-by-character into a container element with a blinking cursor.
 * Returns a promise that resolves when all characters have been typed.
 */
export function typewriteText(
  container: HTMLElement,
  text: string,
): Promise<void> {
  return new Promise((resolve) => {
    const cursor = document.createElement('span');
    cursor.className = CSS_CLASSES.LOG_CURSOR;
    container.appendChild(cursor);

    let charIdx = 0;

    const interval = setInterval(() => {
      if (charIdx < text.length) {
        cursor.before(document.createTextNode(text[charIdx]));
        charIdx++;
      } else {
        clearInterval(interval);
        cursor.remove();
        resolve();
      }
    }, TIMING.CHAR_DELAY);
  });
}
