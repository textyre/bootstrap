type AuthCallbacks = {
  onAuthStart: (username: string) => void;
  onAuthSuccess: () => void;
  onAuthFailure: (message: string) => void;
  onPrompt: (message: string, isSecret: boolean) => void;
  onMessage: (message: string, isError: boolean) => void;
};

let callbacks: AuthCallbacks | null = null;

function getLightDM() {
  return window.lightdm;
}

export function initAuth(cbs: AuthCallbacks): void {
  callbacks = cbs;
  const ldm = getLightDM();
  if (!ldm) return;

  ldm.show_prompt.connect((message: string, type: number) => {
    // type 0 = Question, 1 = Secret
    callbacks?.onPrompt(message, type === 1);
  });

  ldm.show_message.connect((message: string, type: number) => {
    // type 0 = Info, 1 = Error
    callbacks?.onMessage(message, type === 1);
  });

  ldm.authentication_complete.connect(() => {
    if (ldm.is_authenticated) {
      callbacks?.onAuthSuccess();
    } else {
      callbacks?.onAuthFailure('ACCESS DENIED');
    }
  });
}

export function startAuth(username: string): void {
  const ldm = getLightDM();
  if (!ldm) return;

  if (ldm.in_authentication) {
    ldm.cancel_authentication();
  }

  callbacks?.onAuthStart(username);
  ldm.authenticate(username);
}

export function respondToPrompt(response: string): void {
  const ldm = getLightDM();
  if (!ldm) return;
  ldm.respond(response);
}

export function launchSession(): void {
  const ldm = getLightDM();
  if (!ldm) return;
  ldm.start_session(ldm.default_session);
}

export function getFirstUser(): { username: string; displayName: string } | null {
  const ldm = getLightDM();
  if (!ldm || ldm.users.length === 0) return null;
  const u = ldm.users[0];
  return { username: u.username, displayName: u.display_name };
}
