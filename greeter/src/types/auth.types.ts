export interface AuthUser {
  username: string;
  displayName: string;
}

export type AuthCallbacks = {
  onAuthStart: (username: string) => void;
  onAuthSuccess: () => void;
  onAuthFailure: (message: string) => void;
  onPrompt: (message: string, isSecret: boolean) => void;
  onMessage: (message: string, isError: boolean) => void;
};
