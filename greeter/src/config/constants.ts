export const SIG_BYTES = 8;

export const BARCODE = {
  USERNAME: {
    bcid: 'pdf417' as const,
    scale: 1,
    height: 2,
    backgroundcolor: '',
    barcolor: 'ffffff',
    padding: 0,
  },
  SECURITY: {
    bcid: 'pdf417' as const,
    scaleX: 2,
    scaleY: 1,
    height: 12,
    columns: 8,
    backgroundcolor: '',
    barcolor: 'ffffff',
    rotate: 'R' as const,
    padding: 0,
  },
  FINGERPRINT: {
    bcid: 'pdf417' as const,
    scaleX: 3,
    scaleY: 1,
    height: 2,
    columns: 10,
    backgroundcolor: '',
    barcolor: 'ffffff',
    padding: 0,
  },
  FP_HEIGHT: 12,
} as const;

export const CUBE = {
  CENTER_X: 128,
  DEPTH: 36,
  SEGMENTS: 40,
  SIDE_OPACITY: '0.35',
  FRONT_OPACITY: '1',
  BACK_OPACITY: '0.15',
  SVG_NS: 'http://www.w3.org/2000/svg',
} as const;

export const SCRAMBLE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

export const SVG3D_DEFAULTS = {
  // Geometry
  depth: 10,
  bevelEnabled: true,
  bevelThickness: 0.5,
  bevelSize: 0.3,
  targetSize: 5,

  // Material
  color: 0xffffff,  // White (monochrome)
  metalness: 0.0,   // Non-metallic
  roughness: 1.0,   // Matte
  emissive: 0x000000,
  emissiveIntensity: 0.0,
  edgeColor: 0x888888, // Gray edges

  // Camera
  cameraDistance: 15,
  cameraFov: 45,

  // Post-processing
  enableBloom: false,
  bloomIntensity: 0.5,
  bloomThreshold: 0.8,
  bloomRadius: 0.4,

  // Behavior
  autoRotate: false,
  transparent: true,
  antialias: true,
  animations: ['rotate-slow' as const],

  // Quality
  pixelRatio: 2, // Higher quality rendering
} as const;

