import '../styles/main.css';

import { runBootAnimation } from './boot-animation';
import { initClock } from './clock';
import { initCube } from './cube';
import { initTypewriter } from './typewriter';
import { renderUsernameBarcode, renderSecurityBarcode } from './barcode';
import { loadSystemInfo, renderSystemInfo } from './system-info';
import { initAuth, startAuth, respondToPrompt, launchSession, getFirstUser } from './auth';
import { initBackground } from './background';

function getElements() {
  return {
    passwordInput: document.getElementById('password-input') as HTMLInputElement,
    loginForm: document.getElementById('login-form') as HTMLFormElement,
    usernameText: document.getElementById('username-text') as HTMLElement,
    authMessage: document.getElementById('auth-message') as HTMLElement,
  };
}

function showAuthMessage(el: HTMLElement, text: string): void {
  el.textContent = text;
  el.classList.add('visible');
  setTimeout(() => el.classList.remove('visible'), 3000);
}

async function boot(): Promise<void> {
  const els = getElements();
  let waitingForPrompt = false;
  let currentUsername = '';

  // Load system info synchronously before anything else (local file, <5ms)
  const info = await loadSystemInfo();
  const user = getFirstUser();
  const username = user ? user.username : 'unknown';

  // Set os-prefix text before animation starts
  const prefixEl = document.getElementById('os-prefix');
  if (prefixEl) {
    prefixEl.textContent = info.os_name || 'arch';
  }

  // Render system info into DOM (hidden by boot-pre, revealed by animation)
  renderSystemInfo(info);

  // Clock — start ticking (updates hidden elements)
  initClock();

  // Cube — start rAF loop (SVG manipulation on hidden element)
  initCube();

  // Background
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
  if (user) {
    els.usernameText.textContent = user.username.toUpperCase();
    renderUsernameBarcode(user.username);
  } else {
    els.usernameText.textContent = 'UNKNOWN';
    renderUsernameBarcode('unknown');
  }

  // Run boot animation — visual gate (reveals already-rendered content)
  await runBootAnimation();

  // Auth wiring
  initAuth({
    onAuthStart(uname) {
      currentUsername = uname;
      els.passwordInput.value = '';
      els.passwordInput.focus();
    },

    onAuthSuccess() {
      els.authMessage.textContent = 'SESSION STARTING';
      els.authMessage.classList.add('visible');
      setTimeout(() => launchSession(), 500);
    },

    onAuthFailure(message) {
      showAuthMessage(els.authMessage, message);
      setTimeout(() => {
        if (currentUsername) startAuth(currentUsername);
      }, 1000);
    },

    onPrompt(_message, isSecret) {
      if (isSecret) {
        waitingForPrompt = true;
        els.passwordInput.focus();
      }
    },

    onMessage(message, isError) {
      if (isError) {
        showAuthMessage(els.authMessage, message);
      }
    },
  });

  // Start auth after animation
  if (user) {
    currentUsername = user.username;
    startAuth(user.username);
  }

  // Form submit
  els.loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    if (waitingForPrompt) {
      waitingForPrompt = false;
      respondToPrompt(els.passwordInput.value);
    }
  });

  // Focus password after boot animation completes
  els.passwordInput.focus();
}

window.addEventListener('GreeterReady', () => {
  boot();
});

// Local dev: no LightDM, fire boot manually
if (!window.lightdm) {
  document.addEventListener('DOMContentLoaded', () => boot());
}
