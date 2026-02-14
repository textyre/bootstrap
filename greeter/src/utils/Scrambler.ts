import { randomString } from './random';

export class Scrambler {
  constructor(
    private readonly frames: number,
    private readonly interval: number,
  ) {}

  async run(
    finalText: string,
    onFrame: (text: string) => Promise<void>,
  ): Promise<void> {
    for (let frame = 0; frame < this.frames; frame++) {
      await onFrame(randomString(finalText.length));
      await new Promise((r) => setTimeout(r, this.interval));
    }
    await onFrame(finalText);
  }
}
