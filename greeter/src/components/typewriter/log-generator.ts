import type { SystemInfo } from '../../types/global';
import { LOG_TEMPLATES } from '../../config/messages';
import { Formatter } from '../../utils/Formatter';

export interface TextLine {
  type: 'text';
  text: string;
  divider?: boolean;
}

export interface FingerprintLine {
  type: 'fingerprint';
  prefix: string;
  fingerprint: string;
}

export type LogLine = TextLine | FingerprintLine;

export function generateLogLines(info: SystemInfo, username: string): LogLine[] {
  const region = Formatter.region(info.timezone, info.region_prefix);
  const machineUuid = Formatter.machineId(info.machine_id);
  const protocol = Formatter.protocol(info.virtualization_type);

  return [
    {
      type: 'text',
      text: LOG_TEMPLATES.REGION_LINK(region),
    },
    {
      type: 'text',
      text: LOG_TEMPLATES.SYSTEMD_JOURNAL(info.systemd_version, machineUuid),
    },
    {
      type: 'text',
      text: LOG_TEMPLATES.X11_DISPLAY(info.display_output, info.display_resolution),
    },
    {
      type: 'text',
      text: LOG_TEMPLATES.DIVIDER,
      divider: true,
    },
    {
      type: 'text',
      text: LOG_TEMPLATES.BLUME_PROTOCOL(protocol),
    },
    {
      type: 'fingerprint',
      prefix: LOG_TEMPLATES.SENTINEL_PREFIX,
      fingerprint: info.ssh_fingerprint,
    },
    {
      type: 'text',
      text: LOG_TEMPLATES.BLUME_SESSION(username),
    },
  ];
}
