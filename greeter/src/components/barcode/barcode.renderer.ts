/** Render a PDF417 barcode onto a canvas element. */
export async function renderPDF417(
  canvas: HTMLCanvasElement,
  config: Record<string, unknown>,
  text: string,
): Promise<void> {
  const { default: bwipjs } = await import('bwip-js');
  bwipjs.toCanvas(canvas, { ...config, text } as Parameters<typeof bwipjs.toCanvas>[1]);
}
