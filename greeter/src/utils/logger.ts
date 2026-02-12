export function logError(context: string, err: unknown): void {
  console.error(`[greeter:${context}]`, err);
}
