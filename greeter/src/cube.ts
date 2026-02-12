// 3D extruded Arch logo rotation.
// Two faces (front + back) connected by polygon side-walls.
// Each frame: rotate around Y via SVG matrix(), cull back-facing
// side quads, z-sort via DOM order (painter's algorithm).

export function initCube(): void {
  const el = document.querySelector('#arch-logo svg');
  if (!(el instanceof SVGSVGElement)) return;
  const svg: SVGSVGElement = el;

  const pathEl = document.getElementById('arch');
  if (!(pathEl instanceof SVGPathElement)) return;

  const uses = svg.querySelectorAll('use');
  if (uses.length < 2) return;
  const backFace = uses[0];
  const frontFace = uses[1];

  // Sample outline points for side geometry
  const SEG = 40;
  const total = pathEl.getTotalLength();
  const pts: [number, number][] = [];
  for (let i = 0; i < SEG; i++) {
    const p = pathEl.getPointAtLength((i / SEG) * total);
    pts.push([p.x, p.y]);
  }

  // Create side-wall polygons (inserted between back and front)
  const NS = 'http://www.w3.org/2000/svg';
  const sides: SVGPolygonElement[] = [];
  for (let i = 0; i < SEG; i++) {
    const el = document.createElementNS(NS, 'polygon');
    el.setAttribute('fill', 'var(--phosphor)');
    el.setAttribute('opacity', '0.35');
    svg.insertBefore(el, frontFace);
    sides.push(el);
  }

  const CX = 128;   // logo centre x (viewBox units)
  const D = 36;      // extrusion depth
  const PERIOD = 12000;

  function frame(t: number): void {
    const θ = ((t % PERIOD) / PERIOD) * Math.PI * 2;
    const c = Math.cos(θ);
    const s = Math.sin(θ);

    // --- face transforms: matrix(cos,0,0,1, CX*(1-cos)+z*sin, 0) ---
    const fe = CX * (1 - c);          // front (z = 0)
    const be = CX * (1 - c) - D * s;  // back  (z = -D)

    frontFace.setAttribute('transform', `matrix(${c.toFixed(4)},0,0,1,${fe.toFixed(2)},0)`);
    backFace.setAttribute('transform', `matrix(${c.toFixed(4)},0,0,1,${be.toFixed(2)},0)`);

    // Which face is closer to the viewer?
    const frontCloser = c > 0;
    frontFace.setAttribute('opacity', frontCloser ? '1' : '0.15');
    backFace.setAttribute('opacity', frontCloser ? '0.15' : '1');

    // --- side quads ---
    for (let i = 0; i < SEG; i++) {
      const j = (i + 1) % SEG;
      const [x0, y0] = pts[i];
      const [x1, y1] = pts[j];

      // Back-face cull:  normal_z = D · sin(θ) · (y1 − y0)
      if (s * (y1 - y0) <= 0) {
        sides[i].setAttribute('display', 'none');
        continue;
      }
      sides[i].removeAttribute('display');

      // Projected x (y unchanged): CX + (x−CX)·cos + z·sin
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

    // --- z-sort: behind face → sides → in-front face ---
    if (frontCloser) {
      svg.appendChild(backFace);
      for (const q of sides) svg.appendChild(q);
      svg.appendChild(frontFace);
    } else {
      svg.appendChild(frontFace);
      for (const q of sides) svg.appendChild(q);
      svg.appendChild(backFace);
    }

    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}
