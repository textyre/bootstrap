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

