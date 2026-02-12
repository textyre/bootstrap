import type { IEventBus } from '../../services/event-bus';
import type { IAuthService } from '../../services/auth.service';
import { TIMING } from '../../config/constants';
import { SELECTORS, CSS_CLASSES } from '../../config/selectors';
import { MESSAGES } from '../../config/messages';

export function initAuthForm(bus: IEventBus, auth: IAuthService): void {
  const passwordInput = document.getElementById(SELECTORS.PASSWORD_INPUT) as HTMLInputElement;
  const loginForm = document.getElementById(SELECTORS.LOGIN_FORM) as HTMLFormElement;
  const authMessage = document.getElementById(SELECTORS.AUTH_MESSAGE) as HTMLElement;

  let waitingForPrompt = false;
  let currentUsername = '';

  function showMessage(text: string): void {
    authMessage.textContent = text;
    authMessage.classList.add(CSS_CLASSES.VISIBLE);
    setTimeout(() => authMessage.classList.remove(CSS_CLASSES.VISIBLE), TIMING.AUTH_MESSAGE_DISPLAY);
  }

  bus.on('auth:start', ({ username }) => {
    currentUsername = username;
    passwordInput.value = '';
    passwordInput.focus();
  });

  bus.on('auth:success', () => {
    authMessage.textContent = MESSAGES.SESSION_STARTING;
    authMessage.classList.add(CSS_CLASSES.VISIBLE);
    setTimeout(() => auth.launchSession(), TIMING.SESSION_LAUNCH_DELAY);
  });

  bus.on('auth:failure', ({ message }) => {
    showMessage(message);
    setTimeout(() => {
      if (currentUsername) auth.startAuth(currentUsername);
    }, TIMING.AUTH_RETRY_DELAY);
  });

  bus.on('auth:prompt', ({ isSecret }) => {
    if (isSecret) {
      waitingForPrompt = true;
      passwordInput.focus();
    }
  });

  bus.on('auth:message', ({ message, isError }) => {
    if (isError) {
      showMessage(message);
    }
  });

  loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    if (waitingForPrompt) {
      waitingForPrompt = false;
      auth.respondToPrompt(passwordInput.value);
    }
  });
}
