import type { AuthUser } from '../types/auth.types';

export interface ILightDMAdapter {
  readonly available: boolean;
  readonly isAuthenticated: boolean;
  readonly inAuthentication: boolean;
  readonly users: AuthUser[];
  readonly defaultSession: string;
  readonly sessions: Array<{ key: string; name: string }>;

  authenticate(username: string): void;
  cancelAuthentication(): void;
  respond(response: string): void;
  startSession(session: string): void;

  onShowPrompt(handler: (message: string, isSecret: boolean) => void): void;
  onShowMessage(handler: (message: string, isError: boolean) => void): void;
  onAuthenticationComplete(handler: (isAuthenticated: boolean) => void): void;
}

export function createLightDMAdapter(): ILightDMAdapter {
  const ldm = window.lightdm;

  return {
    get available() { return !!ldm; },
    get isAuthenticated() { return ldm?.is_authenticated ?? false; },
    get inAuthentication() { return ldm?.in_authentication ?? false; },
    get users() {
      if (!ldm?.users) return [];
      return ldm.users.map((u) => ({
        username: u.username,
        displayName: u.display_name,
      }));
    },
    get defaultSession() { return ldm?.default_session ?? ''; },
    get sessions() {
      if (!ldm?.sessions) return [];
      return ldm.sessions.map((s) => ({
        key: s.key,
        name: s.name,
      }));
    },

    authenticate(username) { ldm?.authenticate(username); },
    cancelAuthentication() { ldm?.cancel_authentication(); },
    respond(response) { ldm?.respond(response); },
    startSession(session) { ldm?.start_session(session); },

    onShowPrompt(handler) {
      ldm?.show_prompt.connect((message: string, type: number) => {
        handler(message, type === 1);
      });
    },
    onShowMessage(handler) {
      ldm?.show_message.connect((message: string, type: number) => {
        handler(message, type === 1);
      });
    },
    onAuthenticationComplete(handler) {
      ldm?.authentication_complete.connect(() => {
        handler(ldm.is_authenticated);
      });
    },
  };
}
