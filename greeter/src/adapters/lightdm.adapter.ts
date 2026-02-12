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

export class LightDMAdapter implements ILightDMAdapter {
  private readonly ldm = window.lightdm;

  get available(): boolean { return !!this.ldm; }
  get isAuthenticated(): boolean { return this.ldm?.is_authenticated ?? false; }
  get inAuthentication(): boolean { return this.ldm?.in_authentication ?? false; }
  get users(): AuthUser[] {
    if (!this.ldm?.users) return [];
    return this.ldm.users.map((u) => ({
      username: u.username,
      displayName: u.display_name,
    }));
  }
  get defaultSession(): string { return this.ldm?.default_session ?? ''; }
  get sessions(): Array<{ key: string; name: string }> {
    if (!this.ldm?.sessions) return [];
    return this.ldm.sessions.map((s) => ({
      key: s.key,
      name: s.name,
    }));
  }

  authenticate(username: string): void { this.ldm?.authenticate(username); }
  cancelAuthentication(): void { this.ldm?.cancel_authentication(); }
  respond(response: string): void { this.ldm?.respond(response); }
  startSession(session: string): void { this.ldm?.start_session(session); }

  onShowPrompt(handler: (message: string, isSecret: boolean) => void): void {
    this.ldm?.show_prompt.connect((message: string, type: number) => {
      handler(message, type === 1);
    });
  }
  onShowMessage(handler: (message: string, isError: boolean) => void): void {
    this.ldm?.show_message.connect((message: string, type: number) => {
      handler(message, type === 1);
    });
  }
  onAuthenticationComplete(handler: (isAuthenticated: boolean) => void): void {
    this.ldm?.authentication_complete.connect(() => {
      handler(this.ldm!.is_authenticated);
    });
  }
}
