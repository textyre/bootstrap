import '../styles/main.css';

import { BootAnimator } from './animation/boot-orchestrator';
import { Clock } from './components/clock/clock';
import { Cube } from './components/cube/cube';
import { TypewriterController } from './typewriter';
import { SecurityBarcode } from './components/barcode/SecurityBarcode';
import { SystemInfoService } from './services/SystemInfoService';
import { EnvBlock } from './components/env-block/EnvBlock';
import { BackgroundManager } from './BackgroundManager';
import { LightDMAdapter } from './adapters/LightDM.adapter';
import { AuthService } from './services/AuthService';
import { SELECTORS } from './config/selectors';
import { MESSAGES } from './config/messages';

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

  // Set os-prefix text before animation starts
  const prefixEl = document.querySelector(SELECTORS.OS_PREFIX);
  if (prefixEl) {
    prefixEl.textContent = info.os_name || MESSAGES.DEFAULT_OS;
  }

  // Render system info into DOM (hidden by boot-pre, revealed by animation)
  new EnvBlock().render(info);

  // Initialize components
  const clock = new Clock();
  clock.start();
  const cube = new Cube();
  cube.start();

  // DEMO: Svg3DIcon - Uncomment to test 3D icon
  // To use: Add <div class="svg-3d-icon-container boot-pre"></div> to index.html
  const svg3dIcon = new Svg3DIcon('.svg-3d-icon-container', {
    svgPath: '/assets/svgs/arch-logo.svg',
    animations: ['rotate-slow'],
    enableBloom: false,
    depth: 36,           // Как у старого куба
    color: 0xe8e6e3,     // --phosphor цвет для передней/задней грани
    edgeColor: 0x8a8a8a, // Темнее для боковых ребер
    targetSize: 43,      // 90% от контейнера 48x48
    pixelRatio: 6,       // Очень высокое качество
  });
  await svg3dIcon.start();

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
  await authForm.renderUser(username);

  // Start authentication
  auth.startAuth(username);

  // Run boot animation — visual gate (reveals already-rendered content)
  await new BootAnimator().run();

  // Focus password input
  const passwordInput = document.querySelector(SELECTORS.PASSWORD_INPUT) as HTMLInputElement;
  if (passwordInput) passwordInput.focus();
}

window.addEventListener('GreeterReady', () => {
  boot();
});

// Local dev: no LightDM, fire boot manually
if (!window.lightdm) {
  document.addEventListener('DOMContentLoaded', () => boot());
}
