import '../styles/main.css';

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

function boot(): void {
  const els = getElements();
  let waitingForPrompt = false;
  let currentUsername = '';

  // Clock
  initClock();

  // Cube (CSS-only, no-op init)
  initCube();

  // Background
  initBackground();

  // Security barcode (decorative)
  renderSecurityBarcode();

  // System info
  loadSystemInfo().then(renderSystemInfo);

  // Auth wiring
  initAuth({
    onAuthStart(username) {
      currentUsername = username;
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
      // Re-authenticate
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

  // Get user and start
  const user = getFirstUser();
  if (user) {
    currentUsername = user.username;
    els.usernameText.textContent = user.username.toUpperCase();
    renderUsernameBarcode(user.username);
    initTypewriter(user.username);
    startAuth(user.username);
  } else {
    els.usernameText.textContent = 'UNKNOWN';
    initTypewriter('unknown');
  }

  // Form submit
  els.loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    if (waitingForPrompt) {
      waitingForPrompt = false;
      respondToPrompt(els.passwordInput.value);
    }
  });

  // Focus password on load
  els.passwordInput.focus();
}

// Wait for nody-greeter GreeterReady event, or boot immediately in dev
if (window.lightdm) {
  boot();
} else {
  window.addEventListener('GreeterReady', () => boot());
  // Fallback: if GreeterReady never fires (dev mode), boot after timeout
  setTimeout(() => {
    if (!window.lightdm) {
      console.warn('[ctOS] No lightdm detected — running in dev mode');
      boot();
    }
  }, 2000);
}
