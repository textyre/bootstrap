declare module 'bwip-js' {
  interface RenderOptions {
    bcid: string;
    text: string;
    scale?: number;
    scaleX?: number;
    scaleY?: number;
    height?: number;
    width?: number;
    rotate?: 'N' | 'R' | 'L' | 'I';
    padding?: number;
    paddingwidth?: number;
    paddingheight?: number;
    barcolor?: string;
    backgroundcolor?: string;
    bordercolor?: string;
    textcolor?: string;
    columns?: number;
    rows?: number;
    includetext?: boolean;
    textfont?: string;
    textsize?: number;
  }

  interface BwipJs {
    toCanvas(canvas: string | HTMLCanvasElement, opts: RenderOptions): HTMLCanvasElement;
    toSVG(opts: RenderOptions): string;
  }

  const bwipjs: BwipJs;
  export default bwipjs;
}
