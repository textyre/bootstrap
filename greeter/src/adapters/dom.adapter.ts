export class DOMAdapter {
  queryElement<T extends HTMLElement>(
    selector: string,
    type?: new () => T,
  ): T | null {
    const el = document.querySelector(selector);
    if (!el) return null;
    if (type && !(el instanceof type)) return null;
    return el as T;
  }

  createElement<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className?: string,
    textContent?: string,
  ): HTMLElementTagNameMap[K] {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (textContent) el.textContent = textContent;
    return el;
  }
}
