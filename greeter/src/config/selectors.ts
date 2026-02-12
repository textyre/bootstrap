export const SELECTORS = {
  // Background/overlay
  BACKGROUND: 'background',

  // Top-left
  ARCH_LOGO: 'arch-logo',
  CLOCK: 'clock',
  DATE_BOX: 'date-box',
  DATE: 'date',

  // Top-right
  ENV_BLOCK: 'env-block',
  ENV_VALUE: 'env-value',
  IP_VALUE: 'ip-value',

  // Center
  CTOS_LOGO: 'ctos-logo',
  CTOS_BLOCK: 'ctos-block',
  OS_PREFIX: 'os-prefix',
  USERNAME_BARCODE: 'username-barcode',
  USERNAME_TEXT: 'username-text',
  PASSWORD_INPUT: 'password-input',
  LOGIN_FORM: 'login-form',
  LOGIN_BTN: 'login-btn',
  AUTH_MESSAGE: 'auth-message',
  LICENSE: 'license',

  // Bottom-left
  TERMINAL_LOG: 'terminal-log',
  VERSION_PROJECT: 'version-project',
  VERSION_KERNEL: 'version-kernel',

  // Right edge
  RIGHT_EDGE: 'right-edge',
  SECURITY_META: 'security-meta',
  SECURITY_UUID: 'security-uuid',
  SECURITY_COORDS: 'security-coords',
  SECURITY_MATRIX: 'security-matrix',

  // SVG
  ARCH_PATH: 'arch',
} as const;

export const CSS_CLASSES = {
  BOOT_PRE: 'boot-pre',
  BOOT_LOADING: 'boot-loading',
  BOOT_PULLBACK: 'boot-pullback',
  BOOT_REVEAL: 'boot-reveal',
  BOOT_ENTER: 'boot-enter',
  BOOT_FLICKER: 'boot-flicker',
  BOOT_SLIDE: 'boot-slide',
  BOOT_EXPAND: 'boot-expand',
  BOOT_SHIFT_UP: 'boot-shift-up',
  VISIBLE: 'visible',
  LOG_LINE: 'log-line',
  LOG_DIVIDER: 'log-divider',
  LOG_CURSOR: 'log-cursor',
  LOG_FINGERPRINT: 'log-fingerprint',
  FP_CONTAINER: 'fp-container',
  FP_BARCODE: 'fp-barcode',
  FP_TEXT: 'fp-text',
  OS: 'os',
  FORM_CONTAINER: 'form-container',
} as const;
