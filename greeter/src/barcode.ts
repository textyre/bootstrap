import JsBarcode from 'jsbarcode';

function randomHex(length: number): string {
  const chars = '0123456789ABCDEF';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars[Math.floor(Math.random() * chars.length)];
  }
  return result;
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

export function renderSecurityBarcode(): void {
  const canvas = document.getElementById('security-matrix') as HTMLCanvasElement | null;
  const uuidEl = document.getElementById('security-uuid');
  const coordsEl = document.getElementById('security-coords');

  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const w = canvas.width;
  const h = canvas.height;
  const sig = randomHex(16);

  ctx.clearRect(0, 0, w, h);

  const cellSize = 4;
  const cols = Math.floor(w / cellSize);

  // Top zone: data matrix (random squares) — ~40% of height
  const matrixRows = Math.floor((h * 0.4) / cellSize);
  for (let row = 0; row < matrixRows; row++) {
    for (let col = 0; col < cols; col++) {
      if (Math.random() > 0.45) {
        ctx.fillStyle = `rgba(255, 255, 255, ${0.6 + Math.random() * 0.4})`;
        ctx.fillRect(col * cellSize, row * cellSize, cellSize - 1, cellSize - 1);
      }
    }
  }

  // Middle zone: barcode lines — ~40% of height
  const barcodeStart = matrixRows * cellSize + cellSize * 2;
  const barcodeHeight = h * 0.4;
  const barWidth = 2;
  const numBars = Math.floor(w / barWidth);

  for (let i = 0; i < numBars; i++) {
    if (Math.random() > 0.35) {
      const alpha = 0.5 + Math.random() * 0.5;
      ctx.fillStyle = `rgba(255, 255, 255, ${alpha})`;
      ctx.fillRect(i * barWidth, barcodeStart, barWidth - 1, barcodeHeight);
    }
  }

  // Bottom zone: sparse dots — remaining space
  const dotStart = barcodeStart + barcodeHeight + cellSize * 2;
  const dotRows = Math.floor((h - dotStart) / cellSize);
  for (let row = 0; row < dotRows; row++) {
    for (let col = 0; col < cols; col++) {
      if (Math.random() > 0.7) {
        ctx.fillStyle = `rgba(255, 255, 255, ${0.3 + Math.random() * 0.4})`;
        ctx.fillRect(col * cellSize, dotStart + row * cellSize, cellSize - 1, cellSize - 1);
      }
    }
  }

  if (uuidEl) uuidEl.textContent = `SIG:${sig.slice(0, 8)}`;
  if (coordsEl) coordsEl.textContent = 'SYD-AU-NSW-02';
}
