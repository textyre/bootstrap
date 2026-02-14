export class CanvasScaler {
  constructor(
    private readonly target: HTMLCanvasElement,
    private readonly targetHeight: number,
  ) {}

  apply(source: HTMLCanvasElement): void {
    const ratio = this.targetHeight / source.height;
    this.target.width = Math.round(source.width * ratio);
    this.target.height = this.targetHeight;

    const ctx = this.target.getContext('2d');
    if (ctx) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(source, 0, 0, this.target.width, this.target.height);
    }
  }
}
