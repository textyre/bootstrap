export const MESSAGES = {
  AUTH_DENIED: 'ACCESS DENIED',
  SESSION_STARTING: 'SESSION STARTING',
  DEFAULT_OS: 'arch',
  UNKNOWN_USER: 'unknown',
  UNKNOWN_DISPLAY: 'UNKNOWN',
} as const;

export const LOG_TEMPLATES = {
  REGION_LINK: (region: string) =>
    `>> REGION_LINK_ESTABLISHED : ${region}`,
  SYSTEMD_JOURNAL: (version: string, uuid: string) =>
    `>> SYSTEMD_JOURNAL_ACTIVE // v${version} // ${uuid}`,
  X11_DISPLAY: (output: string, resolution: string) =>
    `>> X11_DISPLAY: ${output} <-> :0 // ${resolution}`,
  DIVIDER: '---------- GREETER_UI_INITIALIZING ----------',
  BLUME_PROTOCOL: (protocol: string) =>
    `>> * [BLUME_IDP] Using Protocol::${protocol}`,
  SENTINEL_PREFIX: '>> [SENTINEL ] HOST_KEY_VERIFIED ',
  BLUME_SESSION: (username: string) =>
    `>> [BLUME_IDP] Opened session for user(${username})`,
} as const;
