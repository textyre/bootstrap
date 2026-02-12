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

export function createAuthService(
  ldm: ILightDMAdapter,
  bus: IEventBus,
): IAuthService {
  // Wire LightDM signals to event bus
  ldm.onShowPrompt((message, isSecret) => {
    bus.emit('auth:prompt', { message, isSecret });
  });

  ldm.onShowMessage((message, isError) => {
    bus.emit('auth:message', { message, isError });
  });

  ldm.onAuthenticationComplete((isAuthenticated) => {
    if (isAuthenticated) {
      bus.emit('auth:success', undefined);
    } else {
      bus.emit('auth:failure', { message: MESSAGES.AUTH_DENIED });
    }
  });

  return {
    getFirstUser() {
      const users = ldm.users;
      return users.length > 0 ? users[0] : null;
    },

    startAuth(username) {
      if (ldm.inAuthentication) {
        ldm.cancelAuthentication();
      }
      bus.emit('auth:start', { username });
      ldm.authenticate(username);
    },

    respondToPrompt(response) {
      ldm.respond(response);
    },

    launchSession() {
      let session = ldm.defaultSession;
      const sessions = ldm.sessions;
      if (sessions.length > 0) {
        const valid = sessions.find((s) => s.key === session);
        if (!valid) {
          session = sessions[0].key;
        }
      }
      ldm.startSession(session);
    },
  };
}
