import { CUBE } from '../../config/constants';
import { SELECTORS } from '../../config/selectors';
import { TIMINGS } from '../../config/timings';

export class Cube {
  private rafId: number | null = null;

  start(): void {
    const el = document.querySelector(SELECTORS.ARCH_LOGO + ' svg');
    if (!(el instanceof SVGSVGElement)) return;
    const svg: SVGSVGElement = el;

    const pathEl = document.querySelector(SELECTORS.ARCH_PATH);
    if (!(pathEl instanceof SVGPathElement)) return;

    const uses = svg.querySelectorAll('use');
    if (uses.length < 2) return;
    const backFace = uses[0];
    const frontFace = uses[1];

    const SEG = CUBE.SEGMENTS;
    const total = pathEl.getTotalLength();
    const pts: [number, number][] = [];
    for (let i = 0; i < SEG; i++) {
      const p = pathEl.getPointAtLength((i / SEG) * total);
      pts.push([p.x, p.y]);
    }

    const NS = CUBE.SVG_NS;
    const sides: SVGPolygonElement[] = [];
    for (let i = 0; i < SEG; i++) {
      const poly = document.createElementNS(NS, 'polygon');
      poly.setAttribute('fill', 'var(--text-primary)');
      poly.setAttribute('opacity', CUBE.SIDE_OPACITY);
      svg.insertBefore(poly, frontFace);
      sides.push(poly);
    }

    const CX = CUBE.CENTER_X;
    const D = CUBE.DEPTH;
    const PERIOD = TIMINGS.CUBE_PERIOD;

    this.rafId = requestAnimationFrame((t) => this.frame(t, svg, frontFace, backFace, pts, sides, CX, D, PERIOD));
  }

  stop(): void {
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  private frame(
    t: number,
    svg: SVGSVGElement,
    frontFace: SVGUseElement,
    backFace: SVGUseElement,
    pts: [number, number][],
    sides: SVGPolygonElement[],
    CX: number,
    D: number,
    PERIOD: number,
  ): void {
    const SEG = pts.length;
    const th = ((t % PERIOD) / PERIOD) * Math.PI * 2;
    const c = Math.cos(th);
    const s = Math.sin(th);

    const fe = CX * (1 - c);
    const be = CX * (1 - c) - D * s;

    frontFace.setAttribute('transform', `matrix(${c.toFixed(4)},0,0,1,${fe.toFixed(2)},0)`);
    backFace.setAttribute('transform', `matrix(${c.toFixed(4)},0,0,1,${be.toFixed(2)},0)`);

    const frontCloser = c > 0;
    frontFace.setAttribute('opacity', frontCloser ? CUBE.FRONT_OPACITY : CUBE.BACK_OPACITY);
    backFace.setAttribute('opacity', frontCloser ? CUBE.BACK_OPACITY : CUBE.FRONT_OPACITY);

    for (let i = 0; i < SEG; i++) {
      const j = (i + 1) % SEG;
      const [x0, y0] = pts[i];
      const [x1, y1] = pts[j];

      if (s * (y1 - y0) <= 0) {
        sides[i].setAttribute('display', 'none');
        continue;
      }
      sides[i].removeAttribute('display');

      const fx0 = CX + (x0 - CX) * c;
      const fx1 = CX + (x1 - CX) * c;
      const bx0 = fx0 - D * s;
      const bx1 = fx1 - D * s;

      sides[i].setAttribute('points',
        `${fx0.toFixed(1)},${y0.toFixed(1)} ` +
        `${fx1.toFixed(1)},${y1.toFixed(1)} ` +
        `${bx1.toFixed(1)},${y1.toFixed(1)} ` +
        `${bx0.toFixed(1)},${y0.toFixed(1)}`,
      );
    }

    if (frontCloser) {
      svg.appendChild(backFace);
      for (const q of sides) svg.appendChild(q);
      svg.appendChild(frontFace);
    } else {
      svg.appendChild(frontFace);
      for (const q of sides) svg.appendChild(q);
      svg.appendChild(backFace);
    }

    this.rafId = requestAnimationFrame((nextT) => this.frame(nextT, svg, frontFace, backFace, pts, sides, CX, D, PERIOD));
  }
}
