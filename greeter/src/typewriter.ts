import type { SystemInfo } from './types/global';
import type { LogLine } from './components/typewriter/log-generator';
import { TIMING } from './config/constants';
import { SELECTORS, CSS_CLASSES } from './config/selectors';
import { delay } from './utils/delay';
import { typewriteText } from './components/typewriter/typewriter';
import { generateLogLines } from './components/typewriter/log-generator';
import { renderFingerprintBarcode } from './components/barcode/fingerprint-barcode';

/** Strategy interface for rendering different log line types */
interface LineRenderer {
  render(container: HTMLElement, line: LogLine): Promise<void>;
}

/** Renders a plain text line with typewriter effect */
const textRenderer: LineRenderer = {
  async render(container, line) {
    if (line.type !== 'text') return;
    const lineEl = document.createElement('div');
    lineEl.className = line.divider
      ? CSS_CLASSES.LOG_LINE + ' ' + CSS_CLASSES.LOG_DIVIDER
      : CSS_CLASSES.LOG_LINE;
    container.appendChild(lineEl);
    await typewriteText(lineEl, line.text);
  },
};

/** Renders a fingerprint line: types prefix, then shows scrambling barcode */
const fingerprintRenderer: LineRenderer = {
  async render(container, line) {
    if (line.type !== 'fingerprint') return;
    const lineEl = document.createElement('div');
    lineEl.className = CSS_CLASSES.LOG_LINE + ' ' + CSS_CLASSES.LOG_FINGERPRINT;
    container.appendChild(lineEl);

    // Type prefix using the shared typewriter engine
    await typewriteText(lineEl, line.prefix);

    // Insert barcode, fade in, then scramble
    const { container: barcode, scramble } = renderFingerprintBarcode(line.fingerprint);
    lineEl.appendChild(barcode);
    requestAnimationFrame(() => barcode.classList.add(CSS_CLASSES.VISIBLE));
    await scramble();
  },
};

/** Strategy map: line type -> renderer */
const renderers: Record<string, LineRenderer> = {
  text: textRenderer,
  fingerprint: fingerprintRenderer,
};

export async function initTypewriter(
  info: SystemInfo,
  username: string,
): Promise<void> {
  const container = document.getElementById(SELECTORS.TERMINAL_LOG);
  if (!container) return;

  const lines = generateLogLines(info, username);

  for (const line of lines) {
    const renderer = renderers[line.type];
    if (renderer) {
      await renderer.render(container, line);
    }
    await delay(TIMING.LINE_PAUSE);
  }
}
