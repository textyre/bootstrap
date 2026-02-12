import bwipjs from 'bwip-js';

/** Simple deterministic hash — turns a string into a sequence of pseudo-random bytes. */
function hashBytes(input: string): number[] {
  const bytes: number[] = [];
  let h = 0x811c9dc5; // FNV-1a offset basis
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193); // FNV prime
  }
  // Expand into 256 bytes using the hash as a PRNG seed
  for (let i = 0; i < 256; i++) {
    h ^= i;
    h = Math.imul(h, 0x01000193);
    bytes.push((h >>> 0) & 0xff);
  }
  return bytes;
}

function toHex(bytes: number[], count: number): string {
  return bytes
    .slice(0, count)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
}

export interface SecurityData {
  hostname: string;
  username: string;
  ip: string;
  kernel: string;
}

export function renderUsernameBarcode(username: string): void {
  const el = document.getElementById('username-barcode') as HTMLCanvasElement | null;
  if (!el) return;

  try {
    bwipjs.toCanvas(el, {
      bcid: 'pdf417',
      text: username.toUpperCase(),
      scale: 1,
      height: 2,
      backgroundcolor: '',
      barcolor: 'ffffff',
      padding: 0,
    });
  } catch {
    // Barcode generation failed — leave empty
  }
}

export function renderSecurityBarcode(data: SecurityData): void {
  const canvas = document.getElementById('security-matrix') as HTMLCanvasElement | null;
  const uuidEl = document.getElementById('security-uuid');
  const coordsEl = document.getElementById('security-coords');

  if (!canvas) return;

  // Derive deterministic bytes from real system identity
  const identity = `${data.hostname}:${data.username}:${data.ip}:${data.kernel}`;
  const bytes = hashBytes(identity);
  const sig = toHex(bytes, 8);

  // Encode identity as PDF417 — rotated to fit the vertical strip
  try {
    bwipjs.toCanvas(canvas, {
      bcid: 'pdf417',
      text: identity,
      scaleX: 2,
      scaleY: 1,
      height: 12,
      columns: 8,
      backgroundcolor: '',
      barcolor: 'ffffff',
      rotate: 'R',
      padding: 0,
    });
  } catch {
    // Barcode generation failed — leave empty
  }

  if (uuidEl) uuidEl.textContent = `SIG:${sig}`;
  if (coordsEl) coordsEl.textContent = data.hostname.toUpperCase();
}
