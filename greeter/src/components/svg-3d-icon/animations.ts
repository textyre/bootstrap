import gsap from 'gsap';
import * as THREE from 'three';
import type { AnimationPreset } from '../../types/svg3d.types';
import { TIMINGS } from '../../config/timings';

export class AnimationPresets {
  static create(
    preset: AnimationPreset,
    mesh: THREE.Group,
    material: THREE.Material,
  ): gsap.core.Timeline | gsap.core.Tween {
    switch (preset) {
      case 'rotate-slow':
        return gsap.to(mesh.rotation, {
          y: Math.PI * 2,
          duration: TIMINGS.SVG3D.ROTATION_SLOW / 1000,
          repeat: -1,
          ease: 'none',
        });

      case 'rotate-fast':
        return gsap.to(mesh.rotation, {
          y: Math.PI * 2,
          duration: TIMINGS.SVG3D.ROTATION_FAST / 1000,
          repeat: -1,
          ease: 'none',
        });

      case 'rotate-wobble': {
        const tl = gsap.timeline({ repeat: -1 });
        tl.to(mesh.rotation, {
          y: Math.PI * 2,
          duration: TIMINGS.SVG3D.ROTATION_SLOW / 1000,
          ease: 'none',
        });
        tl.to(
          mesh.rotation,
          {
            z: '+=0.2',
            duration: 1,
            ease: 'elastic.out(1, 0.3)',
            repeat: -1,
            yoyo: true,
          },
          0,
        );
        return tl;
      }

      case 'shake':
        return gsap.to(mesh.position, {
          x: '+=0.1',
          duration: TIMINGS.SVG3D.SHAKE_DURATION / 1000,
          repeat: -1,
          yoyo: true,
          ease: 'power1.inOut',
        });

      case 'pulse-glow':
        // Only works with MeshStandardMaterial
        if ('emissiveIntensity' in material) {
          return gsap.to(material, {
            emissiveIntensity: 0.5,
            duration: TIMINGS.SVG3D.PULSE_DURATION / 1000,
            repeat: -1,
            yoyo: true,
            ease: 'sine.inOut',
          });
        }
        return gsap.timeline();

      case 'bounce':
        return gsap.to(mesh.position, {
          y: '+=0.3',
          duration: TIMINGS.SVG3D.BOUNCE_DURATION / 1000,
          repeat: -1,
          yoyo: true,
          ease: 'bounce.out',
        });

      case 'float':
        return gsap.to(mesh.position, {
          y: '+=0.2',
          duration: TIMINGS.SVG3D.FLOAT_DURATION / 1000,
          repeat: -1,
          yoyo: true,
          ease: 'sine.inOut',
        });

      case 'idle':
      default:
        return gsap.timeline();
    }
  }
}
