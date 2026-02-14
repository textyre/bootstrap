import * as THREE from 'three';
import { SVGLoader } from 'three/examples/jsm/loaders/SVGLoader.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { DOMAdapter } from '../../adapters/DOM.adapter';
import { SVG3D_DEFAULTS } from '../../config/constants';
import type {
  Svg3DIconConfig,
  MaterialConfig,
  BloomConfig,
  AnimationPreset,
} from '../../types/svg3d.types';
import { AnimationPresets } from './animations';

export class Svg3DIcon {
  private readonly adapter = new DOMAdapter();
  private readonly config: Required<Svg3DIconConfig>;
  private readonly container: HTMLElement;

  // three.js core
  private scene: THREE.Scene | null = null;
  private camera: THREE.OrthographicCamera | null = null;
  private renderer: THREE.WebGLRenderer | null = null;
  private mesh: THREE.Group | null = null;

  // Animation
  private rafId: number | null = null;
  private gsapTimelines: (gsap.core.Timeline | gsap.core.Tween)[] = [];

  // Post-processing
  private composer: EffectComposer | null = null;
  private bloomPass: UnrealBloomPass | null = null;

  // Material reference (for animations)
  private material: THREE.MeshStandardMaterial | null = null;

  constructor(containerSelector: string, config: Svg3DIconConfig) {
    const el = this.adapter.queryElement(containerSelector);
    if (!el) throw new Error(`Container ${containerSelector} not found`);

    this.container = el;
    this.config = { ...SVG3D_DEFAULTS, ...config } as Required<Svg3DIconConfig>;
  }

  async start(): Promise<void> {
    try {
      await this.initThreeJS();
      await this.loadSVG();
      this.setupAnimations();
      this.startRenderLoop();
    } catch (error) {
      console.error('[Svg3DIcon] Error during start:', error);
      throw error;
    }
  }

  stop(): void {
    this.cleanup();
  }

  // Public API for runtime control
  setAnimation(preset: AnimationPreset): void {
    if (!this.mesh || !this.material) return;

    // Kill existing animations
    this.gsapTimelines.forEach((tl) => tl.kill());
    this.gsapTimelines = [];

    // Create new animation
    const timeline = AnimationPresets.create(preset, this.mesh, this.material);
    this.gsapTimelines.push(timeline);
  }

  updateMaterial(properties: Partial<MaterialConfig>): void {
    if (!this.material) return;

    if (properties.color !== undefined && 'color' in this.material) {
      this.material.color.setHex(properties.color);
    }

    // Only for MeshStandardMaterial
    if ('metalness' in this.material) {
      const mat = this.material as any;
      if (properties.metalness !== undefined) mat.metalness = properties.metalness;
      if (properties.roughness !== undefined) mat.roughness = properties.roughness;
      if (properties.emissive !== undefined) mat.emissive.setHex(properties.emissive);
      if (properties.emissiveIntensity !== undefined)
        mat.emissiveIntensity = properties.emissiveIntensity;
    }
  }

  updateBloom(properties: BloomConfig): void {
    if (!this.bloomPass) return;

    if (properties.intensity !== undefined) this.bloomPass.strength = properties.intensity;
    if (properties.threshold !== undefined) this.bloomPass.threshold = properties.threshold;
    if (properties.radius !== undefined) this.bloomPass.radius = properties.radius;
  }

  pause(): void {
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
    this.gsapTimelines.forEach((tl) => tl.pause());
  }

  resume(): void {
    this.gsapTimelines.forEach((tl) => tl.resume());
    if (this.rafId === null) {
      this.startRenderLoop();
    }
  }

  // Private methods

  private async initThreeJS(): Promise<void> {
    // Scene
    this.scene = new THREE.Scene();

    // Get container dimensions
    const width = this.container.clientWidth || 100;
    const height = this.container.clientHeight || 100;

    // Use orthographic camera (no perspective distortion, like SVG)
    // Calculate frustum to make object cover 90% of viewport
    const viewportCoverage = 0.9;
    const frustumSize = this.config.targetSize / viewportCoverage;
    const aspect = width / height;
    this.camera = new THREE.OrthographicCamera(
      (frustumSize * aspect) / -2,
      (frustumSize * aspect) / 2,
      frustumSize / 2,
      frustumSize / -2,
      0.1,
      1000,
    );
    this.camera.position.z = 50;

    // Renderer
    this.renderer = new THREE.WebGLRenderer({
      antialias: this.config.antialias,
      alpha: this.config.transparent,
    });

    this.renderer.setSize(width, height);

    // Use configured pixel ratio or window DPR (whichever is higher for quality)
    const pixelRatio = Math.max(
      this.config.pixelRatio || 1,
      window.devicePixelRatio
    );
    this.renderer.setPixelRatio(pixelRatio);

    // Mount canvas to DOM
    this.container.appendChild(this.renderer.domElement);

    // Lighting (required for MeshStandardMaterial)
    // Very strong lighting to make white appear truly white
    const ambientLight = new THREE.AmbientLight(0xffffff, 1.5);
    const directionalLight1 = new THREE.DirectionalLight(0xffffff, 1.5);
    directionalLight1.position.set(5, 5, 5);
    const directionalLight2 = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight2.position.set(-5, -5, 5);
    this.scene.add(ambientLight, directionalLight1, directionalLight2);

    // Test cube removed - SVG working!

    // Post-processing setup
    if (this.config.enableBloom) {
      this.setupPostProcessing();
    }

    // Handle window resize
    this.setupResizeHandler();
  }

  private setupPostProcessing(): void {
    if (!this.renderer || !this.scene || !this.camera) return;

    // Create composer
    this.composer = new EffectComposer(this.renderer);

    // Render pass (renders the scene)
    const renderPass = new RenderPass(this.scene, this.camera);
    this.composer.addPass(renderPass);

    // Bloom effect
    this.bloomPass = new UnrealBloomPass(
      new THREE.Vector2(this.container.clientWidth, this.container.clientHeight),
      this.config.bloomIntensity,
      this.config.bloomRadius,
      this.config.bloomThreshold,
    );
    this.composer.addPass(this.bloomPass);

    // Performance optimization: reduce bloom resolution on high DPI displays
    const pixelRatio = window.devicePixelRatio;
    if (pixelRatio > 2) {
      this.composer.setSize(
        this.container.clientWidth * 0.75,
        this.container.clientHeight * 0.75,
      );
    }
  }

  private setupResizeHandler(): void {
    const handleResize = () => {
      if (!this.camera || !this.renderer) return;

      const width = this.container.clientWidth;
      const height = this.container.clientHeight;

      // Update orthographic camera frustum (90% viewport coverage)
      const viewportCoverage = 0.9;
      const frustumSize = this.config.targetSize / viewportCoverage;
      const aspect = width / height;
      this.camera.left = (frustumSize * aspect) / -2;
      this.camera.right = (frustumSize * aspect) / 2;
      this.camera.top = frustumSize / 2;
      this.camera.bottom = frustumSize / -2;
      this.camera.updateProjectionMatrix();

      this.renderer.setSize(width, height);

      if (this.composer) {
        this.composer.setSize(width, height);
      }
    };

    window.addEventListener('resize', handleResize);
  }

  private async loadSVG(): Promise<void> {
    const loader = new SVGLoader();

    // Load SVG
    const data = await loader.loadAsync(this.config.svgPath);

    // Get all paths from SVG
    const paths = data.paths;

    // Create group to hold all shapes
    const group = new THREE.Group();

    // Create materials for front/back and sides (extrusion)
    const frontBackMaterial = new THREE.MeshStandardMaterial({
      color: this.config.color,
      metalness: this.config.metalness,
      roughness: this.config.roughness,
      emissive: this.config.emissive,
      emissiveIntensity: this.config.emissiveIntensity,
    });

    const sidesMaterial = new THREE.MeshStandardMaterial({
      color: this.config.edgeColor || this.config.color,
      metalness: this.config.metalness,
      roughness: this.config.roughness,
      emissive: this.config.emissive,
      emissiveIntensity: this.config.emissiveIntensity,
    });

    this.material = frontBackMaterial as any;

    // Convert each path to shapes and extrude
    let shapeCount = 0;
    const allGeometries: THREE.BufferGeometry[] = [];

    for (const path of paths) {
      const shapes = SVGLoader.createShapes(path);

      for (const shape of shapes) {
        const geometry = new THREE.ExtrudeGeometry(shape, {
          depth: this.config.depth,
          bevelEnabled: this.config.bevelEnabled,
          bevelThickness: this.config.bevelThickness,
          bevelSize: this.config.bevelSize,
          bevelSegments: 3,
        });

        // Use array of materials: [0] = front/back faces, [1] = sides/bevels
        const mesh = new THREE.Mesh(geometry, [frontBackMaterial, sidesMaterial]);
        group.add(mesh);
        allGeometries.push(geometry);
        shapeCount++;
      }
    }

    // Center and scale the group
    const box = new THREE.Box3().setFromObject(group);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());

    // Center by moving each child mesh
    group.children.forEach((child) => {
      child.position.sub(center);
    });

    // Keep group at origin
    group.position.set(0, 0, 0);

    // Fix SVG orientation (Y-axis is inverted in SVG)
    group.scale.y = -1;

    // Scale to fit viewport
    const maxDim = Math.max(size.x, size.y, size.z);
    const scale = this.config.targetSize / maxDim;

    group.scale.multiplyScalar(scale);

    this.mesh = group;
    this.scene!.add(this.mesh);
  }

  private setupAnimations(): void {
    if (!this.mesh || !this.material) return;

    // Create timelines for each preset
    for (const preset of this.config.animations) {
      const timeline = AnimationPresets.create(preset, this.mesh, this.material);
      this.gsapTimelines.push(timeline);
    }
  }

  private startRenderLoop(): void {
    const animate = () => {
      this.rafId = requestAnimationFrame(animate);

      // Auto-rotation (if enabled and no GSAP rotation)
      if (this.config.autoRotate && this.mesh) {
        this.mesh.rotation.y += 0.005;
      }

      // Render with or without post-processing
      if (this.composer) {
        this.composer.render();
      } else if (this.renderer && this.scene && this.camera) {
        this.renderer.render(this.scene, this.camera);
      }
    };

    animate();
  }

  private cleanup(): void {
    // Cancel animation frame
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    // Kill GSAP timelines
    this.gsapTimelines.forEach((tl) => tl.kill());
    this.gsapTimelines = [];

    // Dispose three.js resources
    if (this.mesh) {
      this.mesh.traverse((child) => {
        if (child instanceof THREE.Mesh || child instanceof THREE.LineSegments) {
          child.geometry.dispose();
          if (Array.isArray(child.material)) {
            child.material.forEach((m) => m.dispose());
          } else {
            child.material.dispose();
          }
        }
      });
    }

    // Dispose renderer
    if (this.renderer) {
      this.renderer.dispose();
      this.renderer.domElement.remove();
    }

    // Dispose composer
    if (this.composer) {
      this.composer.dispose();
    }

    // Clear references
    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.mesh = null;
    this.composer = null;
    this.bloomPass = null;
    this.material = null;
  }
}
