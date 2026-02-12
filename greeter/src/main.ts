import '../styles/main.css';

import { runBootAnimation } from './animation/boot-orchestrator';
import { createClock } from './components/clock/clock';
import { createCube } from './components/cube/cube';
import { initTypewriter } from './typewriter';
import { renderUsernameBarcode } from './components/barcode/username-barcode';
import { renderSecurityBarcode } from './components/barcode/security-barcode';
import { loadSystemInfo } from './services/system-info.service';
import { renderSystemInfo } from './components/env-block/env-block';
import { initBackground } from './background';
import { createLightDMAdapter } from './adapters/lightdm.adapter';
import { createEventBus } from './services/event-bus';
import { createAuthService } from './services/auth.service';
import { initAuthForm } from './components/auth-form/auth-form';
import { SELECTORS } from './config/selectors';
import { MESSAGES } from './config/messages';

async function boot(): Promise<void> {
  // Create core services
  const ldmAdapter = createLightDMAdapter();
  const bus = createEventBus();
  const auth = createAuthService(ldmAdapter, bus);

  // Load system info
  const info = await loadSystemInfo();
  const user = auth.getFirstUser();
  const username = user ? user.username : MESSAGES.UNKNOWN_USER;

  // Set os-prefix text before animation starts
  const prefixEl = document.getElementById(SELECTORS.OS_PREFIX);
  if (prefixEl) {
    prefixEl.textContent = info.os_name || MESSAGES.DEFAULT_OS;
  }

  // Render system info into DOM (hidden by boot-pre, revealed by animation)
  renderSystemInfo(info);

  // Initialize components
  const clock = createClock();
  clock.start();
  const cube = createCube();
  cube.start();
  initBackground();

  // Render all data into DOM before animation starts
  renderSecurityBarcode({
    hostname: info.hostname,
    username,
    ip: info.ip_address,
    kernel: info.kernel,
  });
  initTypewriter(info, username);

  // Set username + barcode before animation
  const usernameText = document.getElementById(SELECTORS.USERNAME_TEXT);
  if (user && usernameText) {
    usernameText.textContent = user.username.toUpperCase();
    renderUsernameBarcode(user.username);
  } else if (usernameText) {
    usernameText.textContent = MESSAGES.UNKNOWN_DISPLAY;
    renderUsernameBarcode(MESSAGES.UNKNOWN_USER);
  }

  // Run boot animation — visual gate (reveals already-rendered content)
  await runBootAnimation();

  // Wire auth form (subscribes to bus events)
  initAuthForm(bus, auth);

  // Start authentication
  if (user) {
    auth.startAuth(user.username);
  }

  // Focus password input
  const passwordInput = document.getElementById(SELECTORS.PASSWORD_INPUT) as HTMLInputElement;
  if (passwordInput) passwordInput.focus();
}

window.addEventListener('GreeterReady', () => {
  boot();
});

// Local dev: no LightDM, fire boot manually
if (!window.lightdm) {
  document.addEventListener('DOMContentLoaded', () => boot());
}
