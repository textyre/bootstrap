import '../styles/main.css';

import { BootAnimator } from './animation/boot-orchestrator';
import { Clock } from './components/clock/clock';
import { Cube } from './components/cube/cube';
import { TypewriterController } from './typewriter';
import { SecurityBarcode } from './components/barcode/SecurityBarcode';
import { loadSystemInfo } from './services/system-info.service';
import { EnvBlock } from './components/env-block/EnvBlock';
import { BackgroundManager } from './BackgroundManager';
import { LightDMAdapter } from './adapters/LightDM.adapter';
import { createEventBus } from './services/event-bus';
import { AuthService } from './services/AuthService';
import { SELECTORS } from './config/selectors';
import { MESSAGES } from './config/messages';

async function boot(): Promise<void> {
  new BackgroundManager().init();

  // Create core services
  const ldmAdapter = new LightDMAdapter();  
  const bus = createEventBus();
  const auth = new AuthService(ldmAdapter, bus);

  // Load system info
  const info = await loadSystemInfo();
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

  // Render all data into DOM before animation starts
  await new SecurityBarcode({
    hostname: info.hostname,
    username,
    ip: info.ip_address,
    kernel: info.kernel,
  }).render();

  // Wire auth form (subscribes to bus events) and render user
  const { AuthForm } = await import('./components/AuthForm/AuthForm');
  const authForm = new AuthForm(bus, auth);
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
