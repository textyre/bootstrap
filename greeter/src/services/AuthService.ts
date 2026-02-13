import type { ILightDMAdapter } from '../adapters/lightdm.adapter';
import type { IEventBus } from './event-bus';
import type { AuthUser } from '../types/auth.types';
import { MESSAGES } from '../config/messages';

export interface IAuthService {
  getFirstUser(): AuthUser | null;
  startAuth(username: string): void;
  respondToPrompt(response: string): void;
  launchSession(): void;
}

export class AuthService implements IAuthService {
  constructor(private readonly ldm: ILightDMAdapter, private readonly bus: IEventBus) {
    this.wireSignals();
  }

  getFirstUser(): AuthUser | null {
    const users = this.ldm.users;
    return users.length > 0 ? users[0] : null;
  }

  startAuth(username: string): void {
    if (this.ldm.inAuthentication) {
      this.ldm.cancelAuthentication();
    }
    this.bus.emit('auth:start', { username });
    this.ldm.authenticate(username);
  }

  respondToPrompt(response: string): void {
    this.ldm.respond(response);
  }

  launchSession(): void {
    let session = this.ldm.defaultSession;
    const sessions = this.ldm.sessions;
    if (sessions.length > 0) {
      const valid = sessions.find((s) => s.key === session);
      if (!valid) {
        session = sessions[0].key;
      }
    }
    this.ldm.startSession(session);
  }

  private wireSignals(): void {
    this.ldm.onShowPrompt((message, isSecret) => {
      this.bus.emit('auth:prompt', { message, isSecret });
    });

    this.ldm.onShowMessage((message, isError) => {
      this.bus.emit('auth:message', { message, isError });
    });

    this.ldm.onAuthenticationComplete((isAuthenticated) => {
      if (isAuthenticated) {
        this.bus.emit('auth:success', undefined);
      } else {
        this.bus.emit('auth:failure', { message: MESSAGES.AUTH_DENIED });
      }
    });
  }
}
