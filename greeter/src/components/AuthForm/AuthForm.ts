import type { IAuthService } from '../../services/AuthService';
import { bus } from '../../services/bus';
import { TIMINGS } from '../../config/timings';
import { SELECTORS, CSS_CLASSES } from '../../config/selectors';
import { MESSAGES } from '../../config/messages';
import { renderUsernameBarcode } from '../barcode/username-barcode';

export class AuthForm {
  private waitingForPrompt = false;
  private currentUsername = '';
  private readonly passwordInput: HTMLInputElement;
  private readonly loginForm: HTMLFormElement;
  private readonly authMessage: HTMLElement;

  constructor(private readonly auth: IAuthService) {
    this.passwordInput = document.querySelector(SELECTORS.PASSWORD_INPUT) as HTMLInputElement;
    this.loginForm = document.querySelector(SELECTORS.LOGIN_FORM) as HTMLFormElement;
    this.authMessage = document.querySelector(SELECTORS.AUTH_MESSAGE) as HTMLElement;
    this.bindEvents();
  }

  async renderUser(username: string): Promise<void> {
    const usernameText = document.querySelector(SELECTORS.USERNAME_TEXT);
    if (usernameText) {
      usernameText.textContent = username.toUpperCase();
    }
    await renderUsernameBarcode(username);
  }

  private bindEvents(): void {
    bus.on('auth:start', ({ username }) => {
      this.currentUsername = username;
      this.passwordInput.value = '';
      this.passwordInput.focus();
    });

    bus.on('auth:success', () => {
      this.authMessage.textContent = MESSAGES.SESSION_STARTING;
      this.authMessage.classList.add(CSS_CLASSES.VISIBLE);
      setTimeout(() => this.auth.launchSession(), TIMINGS.AUTH.SESSION_LAUNCH_DELAY);
    });

    bus.on('auth:failure', ({ message }) => {
      this.showMessage(message);
      setTimeout(() => {
        if (this.currentUsername) this.auth.startAuth(this.currentUsername);
      }, TIMINGS.AUTH.AUTH_RETRY_DELAY);
    });

    bus.on('auth:prompt', ({ isSecret }) => {
      if (isSecret) {
        this.waitingForPrompt = true;
        this.passwordInput.focus();
      }
    });

    bus.on('auth:message', ({ message, isError }) => {
      if (isError) {
        this.showMessage(message);
      }
    });

    this.loginForm.addEventListener('submit', (e) => {
      e.preventDefault();
      if (this.waitingForPrompt) {
        this.waitingForPrompt = false;
        this.auth.respondToPrompt(this.passwordInput.value);
      }
    });
  }

  private showMessage(text: string): void {
    this.authMessage.textContent = text;
    this.authMessage.classList.add(CSS_CLASSES.VISIBLE);
    setTimeout(() => this.authMessage.classList.remove(CSS_CLASSES.VISIBLE), TIMINGS.AUTH.AUTH_MESSAGE_DISPLAY);
  }
}
