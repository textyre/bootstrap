import bwipjs from 'bwip-js';

/** Render a PDF417 barcode onto a canvas element. */
export function renderPDF417(
  canvas: HTMLCanvasElement,
  config: Record<string, unknown>,
  text: string,
): void {
  bwipjs.toCanvas(canvas, { ...config, text } as Parameters<typeof bwipjs.toCanvas>[1]);
}
