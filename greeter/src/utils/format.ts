const VIRT_PROTOCOL_MAP: Record<string, string> = {
  virtualbox: 'VBOX::X11',
  kvm: 'KVM::X11',
  vmware: 'VMWARE::X11',
  'bare-metal': 'X11',
};

export function formatRegion(timezone: string, prefix: string): string {
  const parts = timezone.split('/');
  const city = (parts[parts.length - 1] || 'UNKNOWN').toUpperCase().replace(/_/g, '-');
  const code = prefix
    ? prefix.toUpperCase()
    : (parts[0] || 'XX').substring(0, 2).toUpperCase();
  return `${code}-${city}-1`;
}

export function formatMachineId(id: string): string {
  if (id.length === 32) {
    return `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`;
  }
  return id;
}

export function formatProtocol(virtType: string): string {
  const t = virtType.toLowerCase();
  return VIRT_PROTOCOL_MAP[t] ?? `${virtType.toUpperCase()}::X11`;
}
