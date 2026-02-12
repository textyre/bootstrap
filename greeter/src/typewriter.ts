import bwipjs from 'bwip-js';
import type { SystemInfo } from './types/global';

const CHAR_DELAY = 18;
const LINE_PAUSE = 400;

interface TextLine {
  type: 'text';
  text: string;
  divider?: boolean;
}

interface FingerprintLine {
  type: 'fingerprint';
  prefix: string;
  fingerprint: string;
}

type LogLine = TextLine | FingerprintLine;

function formatRegion(timezone: string, prefix: string): string {
  const parts = timezone.split('/');
  const city = (parts[parts.length - 1] || 'UNKNOWN').toUpperCase().replace(/_/g, '-');
  const code = prefix
    ? prefix.toUpperCase()
    : (parts[0] || 'XX').substring(0, 2).toUpperCase();
  return `${code}-${city}-1`;
}

function formatMachineId(id: string): string {
  if (id.length === 32) {
    return `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`;
  }
  return id;
}

function formatProtocol(virtType: string): string {
  const t = virtType.toLowerCase();
  if (t === 'virtualbox') return 'VBOX::X11';
  if (t === 'kvm') return 'KVM::X11';
  if (t === 'vmware') return 'VMWARE::X11';
  if (t === 'bare-metal') return 'X11';
  return `${virtType.toUpperCase()}::X11`;
}

function generateLogLines(info: SystemInfo, username: string): LogLine[] {
  const region = formatRegion(info.timezone, info.region_prefix);
  const machineUuid = formatMachineId(info.machine_id);
  const protocol = formatProtocol(info.virtualization_type);

  return [
    {
      type: 'text',
      text: `>> REGION_LINK_ESTABLISHED : ${region}`,
    },
    {
      type: 'text',
      text: `>> SYSTEMD_JOURNAL_ACTIVE // v${info.systemd_version} // ${machineUuid}`,
    },
    {
      type: 'text',
      text: `>> X11_DISPLAY: ${info.display_output} <-> :0 // ${info.display_resolution}`,
    },
    {
      type: 'text',
      text: `---------- GREETER_UI_INITIALIZING ----------`,
      divider: true,
    },
    {
      type: 'text',
      text: `>> * [BLUME_IDP] Using Protocol::${protocol}`,
    },
    {
      type: 'fingerprint',
      prefix: `>> [SENTINEL ] HOST_KEY_VERIFIED `,
      fingerprint: info.ssh_fingerprint,
    },
    {
      type: 'text',
      text: `>> [BLUME_IDP] Opened session for user(${username})`,
    },
  ];
}

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

const SCRAMBLE_FRAMES = 15;
const SCRAMBLE_INTERVAL = 60;
const SCRAMBLE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

function randomString(length: number): string {
  let s = '';
  for (let i = 0; i < length; i++) {
    s += SCRAMBLE_CHARS[Math.floor(Math.random() * SCRAMBLE_CHARS.length)];
  }
  return s;
}

const PDF417_OPTS = {
  bcid: 'pdf417' as const,
  scaleX: 3,
  scaleY: 1,
  height: 2,
  columns: 10,
  backgroundcolor: '',
  barcolor: 'ffffff',
  padding: 0,
};

const FP_HEIGHT = 12;

function renderToCanvas(canvas: HTMLCanvasElement, text: string): void {
  try {
    const tmp = document.createElement('canvas');
    bwipjs.toCanvas(tmp, { ...PDF417_OPTS, text });

    const ratio = FP_HEIGHT / tmp.height;
    canvas.width = Math.round(tmp.width * ratio);
    canvas.height = FP_HEIGHT;

    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(tmp, 0, 0, canvas.width, canvas.height);
    }
  } catch {
    // ignore
  }
}

function renderFingerprintBarcode(fingerprint: string): {
  container: HTMLElement;
  scramble: () => Promise<void>;
} {
  const container = document.createElement('span');
  container.className = 'fp-container';

  const canvas = document.createElement('canvas');
  canvas.classList.add('fp-barcode');

  renderToCanvas(canvas, randomString(fingerprint.length));

  const textEl = document.createElement('span');
  textEl.className = 'fp-text';
  textEl.textContent = fingerprint;

  container.appendChild(canvas);
  container.appendChild(textEl);

  const scramble = (): Promise<void> =>
    new Promise((resolve) => {
      let frame = 0;
      const interval = setInterval(() => {
        frame++;
        if (frame < SCRAMBLE_FRAMES) {
          renderToCanvas(canvas, randomString(fingerprint.length));
        } else {
          clearInterval(interval);
          renderToCanvas(canvas, fingerprint);
          resolve();
        }
      }, SCRAMBLE_INTERVAL);
    });

  return { container, scramble };
}

async function typewriteFingerprintLine(
  container: HTMLElement,
  prefix: string,
  fingerprint: string,
): Promise<void> {
  const lineEl = document.createElement('div');
  lineEl.className = 'log-line log-fingerprint';
  container.appendChild(lineEl);

  // Type prefix character by character
  await new Promise<void>((resolve) => {
    const cursor = document.createElement('span');
    cursor.className = 'log-cursor';
    lineEl.appendChild(cursor);

    let charIdx = 0;
    const interval = setInterval(() => {
      if (charIdx < prefix.length) {
        cursor.before(document.createTextNode(prefix[charIdx]));
        charIdx++;
      } else {
        clearInterval(interval);
        cursor.remove();
        resolve();
      }
    }, CHAR_DELAY);
  });

  // Insert barcode, fade in, then run scramble animation
  const { container: barcode, scramble } = renderFingerprintBarcode(fingerprint);
  lineEl.appendChild(barcode);
  requestAnimationFrame(() => barcode.classList.add('visible'));
  await scramble();
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export async function initTypewriter(
  info: SystemInfo,
  username: string,
): Promise<void> {
  const container = document.getElementById('terminal-log');
  if (!container) return;

  const lines = generateLogLines(info, username);

  for (const line of lines) {
    if (line.type === 'fingerprint') {
      await typewriteFingerprintLine(
        container,
        line.prefix,
        line.fingerprint,
      );
    } else {
      await typewriteLine(container, line.text, line.divider ?? false);
    }
    await delay(LINE_PAUSE);
  }
}
