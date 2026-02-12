import type { SystemInfo } from './types/global';
import type { LogLine } from './components/typewriter/log-generator';
import { TIMING } from './config/constants';
import { SELECTORS, CSS_CLASSES } from './config/selectors';
import { delay } from './utils/delay';
import { Typewriter } from './components/typewriter/typewriter';
import { generateLogLines } from './components/typewriter/log-generator';
import { FingerprintBarcode } from './components/barcode/fingerprint-barcode';

/**
 * Orchestrates the terminal log typewriter sequence.
 * Generates log lines from system info and renders them one by one
 * using the appropriate renderer for each line type.
 */
export class TypewriterController {
  constructor(
    private readonly info: SystemInfo,
    private readonly username: string,
  ) {}

  async run(): Promise<void> {
    const container = document.querySelector(SELECTORS.TERMINAL_LOG) as HTMLElement | null;
    if (!container) return;

    const lines = generateLogLines(this.info, this.username);

    for (const line of lines) {
      await this.renderLine(container, line);
      await delay(TIMING.LINE_PAUSE);
    }
  }

  private async renderLine(container: HTMLElement, line: LogLine): Promise<void> {
    const renderer = this.renderers[line.type];
    if (renderer) await renderer(container, line);
  }

  private renderers: Record<string, (container: HTMLElement, line: LogLine) => Promise<void>> = {
    text: this.renderText.bind(this),
    fingerprint: this.renderFingerprint.bind(this),
  };

  private async renderText(container: HTMLElement, line: LogLine): Promise<void> {
    if (line.type !== 'text') return;
    const lineEl = document.createElement('div');
    lineEl.className = line.divider
      ? CSS_CLASSES.LOG_LINE + ' ' + CSS_CLASSES.LOG_DIVIDER
      : CSS_CLASSES.LOG_LINE;
    container.appendChild(lineEl);
    await new Typewriter(lineEl, line.text).type();
  }

  private async renderFingerprint(container: HTMLElement, line: LogLine): Promise<void> {
    if (line.type !== 'fingerprint') return;
    const lineEl = document.createElement('div');
    lineEl.className = CSS_CLASSES.LOG_LINE + ' ' + CSS_CLASSES.LOG_FINGERPRINT;
    container.appendChild(lineEl);

    // Type prefix using the shared typewriter engine
    await new Typewriter(lineEl, line.prefix).type();

    // Insert barcode, fade in, then scramble
    const fp = new FingerprintBarcode(line.fingerprint);
    lineEl.appendChild(fp.container);
    requestAnimationFrame(() => fp.container.classList.add(CSS_CLASSES.VISIBLE));
    await fp.scramble();
  }
}
