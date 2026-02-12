import '../styles/main.css';

import { BootAnimator } from './animation/boot-orchestrator';
import { Clock } from './components/clock/clock';
import { Cube } from './components/cube/cube';
import { TypewriterController } from './typewriter';
import { renderUsernameBarcode } from './components/barcode/username-barcode';
import { SecurityBarcode } from './components/barcode/security-barcode';
import { loadSystemInfo } from './services/system-info.service';
import { EnvBlock } from './components/env-block/env-block';
import { initBackground } from './background';
import { LightDMAdapter } from './adapters/lightdm.adapter';
import { createEventBus } from './services/event-bus';
import { AuthService } from './services/auth.service';
import { AuthForm } from './components/auth-form/auth-form';
import { SELECTORS } from './config/selectors';
import { MESSAGES } from './config/messages';

async function boot(): Promise<void> {
  // Create core services
  const ldmAdapter = new LightDMAdapter();
  const bus = createEventBus();
  const auth = new AuthService(ldmAdapter, bus);

  // Load system info
  const info = await loadSystemInfo();
  const user = auth.getFirstUser();
  const username = user ? user.username : MESSAGES.UNKNOWN_USER;

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
  initBackground();

  // Render all data into DOM before animation starts
  await new SecurityBarcode({
    hostname: info.hostname,
    username,
    ip: info.ip_address,
    kernel: info.kernel,
  }).render();
  new TypewriterController(info, username).run();

  // Set username + barcode before animation
  const usernameText = document.querySelector(SELECTORS.USERNAME_TEXT);
  if (user && usernameText) {
    usernameText.textContent = user.username.toUpperCase();
    renderUsernameBarcode(user.username);
  } else if (usernameText) {
    usernameText.textContent = MESSAGES.UNKNOWN_DISPLAY;
    renderUsernameBarcode(MESSAGES.UNKNOWN_USER);
  }

  // Run boot animation — visual gate (reveals already-rendered content)
  await new BootAnimator().run();

  // Wire auth form (subscribes to bus events)
  new AuthForm(bus, auth);

  // Start authentication
  if (user) {
    auth.startAuth(user.username);
  }

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
