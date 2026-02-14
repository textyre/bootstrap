export type AnimationPreset =
  | 'rotate-slow'
  | 'rotate-fast'
  | 'rotate-wobble'
  | 'shake'
  | 'pulse-glow'
  | 'bounce'
  | 'float'
  | 'idle';

// Predefined color presets
export const SVG3D_COLORS = {
  // Monochrome (grayscale)
  WHITE: 0xffffff,
  LIGHT_GRAY: 0xcccccc,
  GRAY: 0x888888,
  DARK_GRAY: 0x444444,
  BLACK: 0x000000,

  // Cyan/Blue theme (existing)
  CYAN: 0x00ffff,
  PHOSPHOR: 0x00ff00,

  // Additional colors
  RED: 0xff0000,
  ORANGE: 0xff6600,
  YELLOW: 0xffff00,
  GREEN: 0x00ff00,
  BLUE: 0x0000ff,
  PURPLE: 0x9900ff,
  MAGENTA: 0xff00ff,
} as const;

export type Svg3DColor = (typeof SVG3D_COLORS)[keyof typeof SVG3D_COLORS];

export interface Svg3DIconConfig {
  // SVG source (required)
  svgPath: string;

  // Geometry (optional, defaults from constants)
  depth?: number;
  bevelEnabled?: boolean;
  bevelThickness?: number;
  bevelSize?: number;
  targetSize?: number;

  // Material
  color?: number;
  metalness?: number;
  roughness?: number;
  emissive?: number;
  emissiveIntensity?: number;
  edgeColor?: number; // Color for edges/wireframe

  // Animation
  animations?: AnimationPreset[];

  // Post-processing
  enableBloom?: boolean;
  bloomIntensity?: number;
  bloomThreshold?: number;
  bloomRadius?: number;

  // Camera
  cameraDistance?: number;
  cameraFov?: number;

  // Behavior
  autoRotate?: boolean;
  transparent?: boolean;
  antialias?: boolean;

  // Quality
  pixelRatio?: number;
}

export interface MaterialConfig {
  color?: number;
  metalness?: number;
  roughness?: number;
  emissive?: number;
  emissiveIntensity?: number;
}

export interface BloomConfig {
  intensity?: number;
  threshold?: number;
  radius?: number;
}
