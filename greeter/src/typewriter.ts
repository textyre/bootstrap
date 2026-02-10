function randomHex(length: number): string {
  const chars = '0123456789ABCDEF';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars[Math.floor(Math.random() * chars.length)];
  }
  return result;
}

function randomUUID(): string {
  const s = (n: number) => randomHex(n);
  return `${s(8)}-${s(4)}-${s(4)}-${s(4)}-${s(12)}`;
}

function generateLogLines(username: string): string[] {
  return [
    `>> REGION_LINK_ESTABLISHED : AU-SOUTH-EAST-2`,
    `>> LOG_STREAM_CONNECTED // ${randomUUID()}`,
    `>> WL_OUTPUT_FOUND: DP-3 <-> ADDR_PTR: 0x${randomHex(8)}`,
    `---------- GREETER_UI_INITIALIZING ----------`,
    `>> * [BLUME_IDP] Using Protocol::TEST`,
    `>> [SENTINEL ] CIPHER_NEGOTIATED <-> bnet://0x${randomHex(8)}:1443`,
    `>> [BLUME_IDP] Opened session for user(${username})`,
  ];
}

const CHAR_DELAY = 18;
const LINE_PAUSE = 400;

function typewriteLine(
  container: HTMLElement,
  text: string,
  isDivider: boolean,
): Promise<void> {
  return new Promise((resolve) => {
    const lineEl = document.createElement('div');
    lineEl.className = isDivider ? 'log-line log-divider' : 'log-line';
    container.appendChild(lineEl);

    const cursor = document.createElement('span');
    cursor.className = 'log-cursor';
    lineEl.appendChild(cursor);

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
    }, CHAR_DELAY);
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export async function initTypewriter(username: string): Promise<void> {
  const container = document.getElementById('terminal-log');
  if (!container) return;

  const lines = generateLogLines(username);

  for (const line of lines) {
    const isDivider = line.startsWith('---');
    await typewriteLine(container, line, isDivider);
    await delay(LINE_PAUSE);
  }
}
