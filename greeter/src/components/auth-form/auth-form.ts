import type { IEventBus } from '../../services/event-bus';
import type { IAuthService } from '../../services/auth.service';
import { TIMING } from '../../config/constants';
import { SELECTORS, CSS_CLASSES } from '../../config/selectors';
import { MESSAGES } from '../../config/messages';

export class AuthForm {
  private waitingForPrompt = false;
  private currentUsername = '';
  private readonly passwordInput: HTMLInputElement;
  private readonly loginForm: HTMLFormElement;
  private readonly authMessage: HTMLElement;

  constructor(private readonly bus: IEventBus, private readonly auth: IAuthService) {
    this.passwordInput = document.querySelector(SELECTORS.PASSWORD_INPUT) as HTMLInputElement;
    this.loginForm = document.querySelector(SELECTORS.LOGIN_FORM) as HTMLFormElement;
    this.authMessage = document.querySelector(SELECTORS.AUTH_MESSAGE) as HTMLElement;
    this.bindEvents();
  }

  private bindEvents(): void {
    this.bus.on('auth:start', ({ username }) => {
      this.currentUsername = username;
      this.passwordInput.value = '';
      this.passwordInput.focus();
    });

    this.bus.on('auth:success', () => {
      this.authMessage.textContent = MESSAGES.SESSION_STARTING;
      this.authMessage.classList.add(CSS_CLASSES.VISIBLE);
      setTimeout(() => this.auth.launchSession(), TIMING.SESSION_LAUNCH_DELAY);
    });

    this.bus.on('auth:failure', ({ message }) => {
      this.showMessage(message);
      setTimeout(() => {
        if (this.currentUsername) this.auth.startAuth(this.currentUsername);
      }, TIMING.AUTH_RETRY_DELAY);
    });

    this.bus.on('auth:prompt', ({ isSecret }) => {
      if (isSecret) {
        this.waitingForPrompt = true;
        this.passwordInput.focus();
      }
    });

    this.bus.on('auth:message', ({ message, isError }) => {
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
    setTimeout(() => this.authMessage.classList.remove(CSS_CLASSES.VISIBLE), TIMING.AUTH_MESSAGE_DISPLAY);
  }
}
