import '../styles/main.css';

import { BootAnimator } from './animation/BootAnimator';
import { Clock } from './components/Clock';
import { TypewriterController } from './TypewriterController';
import { SecurityBarcode } from './components/Barcode/SecurityBarcode';
import { SystemInfoService } from './services/SystemInfoService';
import { EnvBlock } from './components/EnvBlock/EnvBlock';
import { BackgroundManager } from './BackgroundManager';
import { LightDMAdapter } from './adapters/LightDM.adapter';
import { AuthService } from './services/AuthService';

// Uncomment to test Svg3DIcon component
import { Svg3DIcon } from './components/svg-3d-icon/Svg3DIcon';
// import { SVG3D_PRESETS } from './components/svg-3d-icon/presets';

async function boot(): Promise<void> {
  new BackgroundManager().init();

  // Create core services
  const ldmAdapter = new LightDMAdapter();  
  const auth = new AuthService(ldmAdapter);

  // Load system info
  const info = await new SystemInfoService().load();
  const username = auth.getUsernameForDisplay();
  
  new TypewriterController(info, username).run();

  // Render system info into DOM (hidden by boot-pre, revealed by animation)
  new EnvBlock().render(info);

  // Initialize components
  const clock = new Clock();
  clock.start();

  const archIcon = new Svg3DIcon('.svg-3d-icon-arch', {
    svgPath: '/assets/svgs/arch-logo.svg',
    animations: ['rotate-slow'],
    enableBloom: false,
    depth: 36,
    color: 0xe8e6e3,
    edgeColor: 0x8a8a8a,
    targetSize: 43,
    pixelRatio: 6,
  });

  // const gentooIcon = new Svg3DIcon('.svg-3d-icon-gentoo', {
  //   svgPath: '/assets/svgs/gentoo-3d.svg',
  //   animations: ['rotate-slow'],
  //   enableBloom: false,
  //   depth: 36,
  //   color: 0xe8e6e3,
  //   edgeColor: 0x8a8a8a,
  //   targetSize: 43,
  //   pixelRatio: 6,
  //   initialRotation: { x: -45 },
  // });

  // const ubuntuIcon = new Svg3DIcon('.svg-3d-icon-ubuntu', {
  //   svgPath: '/assets/svgs/ubuntu-3d.svg',
  //   animations: ['rotate-slow'],
  //   enableBloom: false,
  //   depth: 36,
  //   color: 0xe8e6e3,
  //   edgeColor: 0x8a8a8a,
  //   targetSize: 43,
  //   pixelRatio: 6,
  // });

  await Promise.all([archIcon.start(), gentooIcon.start(), ubuntuIcon.start()]);

  // Render all data into DOM before animation starts
  await new SecurityBarcode({
    hostname: info.hostname,
    username,
    ip: info.ip_address,
    kernel: info.kernel,
  }).render();

  // Wire auth form (subscribes to bus events) and render user
  const { AuthForm } = await import('./components/AuthForm/AuthForm');
  const authForm = new AuthForm(auth);
  authForm.renderOsPrefix(info.os_name);
  await authForm.renderUser(username);

  // Start authentication
  auth.startAuth(username);

  // Run boot animation — visual gate (reveals already-rendered content)
  await new BootAnimator().run();

  // Focus password input
  authForm.focus();
}

window.addEventListener('GreeterReady', () => {
  boot();
});

// Local dev: no LightDM, fire boot manually
if (!window.lightdm) {
  document.addEventListener('DOMContentLoaded', () => boot());
}
