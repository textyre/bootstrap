import JsBarcode from 'jsbarcode';

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
  const el = document.getElementById('username-barcode');
  if (!el) return;

  try {
    JsBarcode(el, username.toUpperCase(), {
      format: 'CODE128',
      lineColor: '#ffffff',
      background: 'transparent',
      displayValue: false,
      height: 40,
      width: 1,
      margin: 0,
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

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const w = canvas.width;
  const h = canvas.height;

  // Derive deterministic bytes from real system identity
  const identity = `${data.hostname}:${data.username}:${data.ip}:${data.kernel}`;
  const bytes = hashBytes(identity);
  const sig = toHex(bytes, 8);

  ctx.clearRect(0, 0, w, h);

  const cellSize = 4;
  const cols = Math.floor(w / cellSize);
  let byteIdx = 0;

  const nextByte = (): number => {
    const b = bytes[byteIdx % bytes.length];
    byteIdx++;
    return b;
  };

  // Top zone: data matrix — hostname + username encoded as bit pattern
  const matrixRows = Math.floor((h * 0.4) / cellSize);
  for (let row = 0; row < matrixRows; row++) {
    for (let col = 0; col < cols; col++) {
      const b = nextByte();
      if (b > 115) {
        const alpha = 0.6 + (b / 255) * 0.4;
        ctx.fillStyle = `rgba(255, 255, 255, ${alpha})`;
        ctx.fillRect(col * cellSize, row * cellSize, cellSize - 1, cellSize - 1);
      }
    }
  }

  // Middle zone: barcode lines — IP + kernel as vertical bars
  const barcodeStart = matrixRows * cellSize + cellSize * 2;
  const barcodeHeight = h * 0.4;
  const barWidth = 2;
  const numBars = Math.floor(w / barWidth);

  for (let i = 0; i < numBars; i++) {
    const b = nextByte();
    if (b > 90) {
      const alpha = 0.5 + (b / 255) * 0.5;
      ctx.fillStyle = `rgba(255, 255, 255, ${alpha})`;
      ctx.fillRect(i * barWidth, barcodeStart, barWidth - 1, barcodeHeight);
    }
  }

  // Bottom zone: sparse dots — checksum scatter
  const dotStart = barcodeStart + barcodeHeight + cellSize * 2;
  const dotRows = Math.floor((h - dotStart) / cellSize);
  for (let row = 0; row < dotRows; row++) {
    for (let col = 0; col < cols; col++) {
      const b = nextByte();
      if (b > 180) {
        const alpha = 0.3 + (b / 255) * 0.4;
        ctx.fillStyle = `rgba(255, 255, 255, ${alpha})`;
        ctx.fillRect(col * cellSize, dotStart + row * cellSize, cellSize - 1, cellSize - 1);
      }
    }
  }

  if (uuidEl) uuidEl.textContent = `SIG:${sig}`;
  if (coordsEl) coordsEl.textContent = data.hostname.toUpperCase();
}
