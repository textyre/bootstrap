export function queryElement<T extends HTMLElement>(
  id: string,
  type?: new () => T,
): T | null {
  const el = document.getElementById(id);
  if (!el) return null;
  if (type && !(el instanceof type)) return null;
  return el as T;
}

export function createElement<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  textContent?: string,
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (textContent) el.textContent = textContent;
  return el;
}
