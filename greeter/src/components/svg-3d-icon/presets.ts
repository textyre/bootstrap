import type { Svg3DIconConfig } from '../../types/svg3d.types';
import { SVG3D_DEFAULTS } from '../../config/constants';

export const SVG3D_PRESETS: Record<string, Partial<Svg3DIconConfig>> = {
  minimal: {
    ...SVG3D_DEFAULTS,
    animations: ['rotate-slow'],
    enableBloom: false,
    metalness: 0.5,
    roughness: 0.5,
  },

  cyberpunk: {
    ...SVG3D_DEFAULTS,
    animations: ['rotate-slow', 'pulse-glow'],
    enableBloom: true,
    bloomIntensity: 0.8,
    metalness: 0.9,
    roughness: 0.1,
    emissiveIntensity: 0.3,
  },

  energetic: {
    ...SVG3D_DEFAULTS,
    animations: ['rotate-fast', 'rotate-wobble', 'pulse-glow'],
    enableBloom: true,
    bloomIntensity: 0.9,
    metalness: 0.7,
    roughness: 0.3,
  },

  floating: {
    ...SVG3D_DEFAULTS,
    animations: ['float', 'rotate-slow'],
    enableBloom: false,
    metalness: 0.6,
    roughness: 0.4,
  },
} as const;
