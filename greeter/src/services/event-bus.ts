type EventMap = {
  'auth:start': { username: string };
  'auth:success': undefined;
  'auth:failure': { message: string };
  'auth:prompt': { message: string; isSecret: boolean };
  'auth:message': { message: string; isError: boolean };
};

type EventHandler<T> = (data: T) => void;

export interface IEventBus {
  on<K extends keyof EventMap>(event: K, handler: EventHandler<EventMap[K]>): () => void;
  emit<K extends keyof EventMap>(event: K, data: EventMap[K]): void;
}

export function createEventBus(): IEventBus {
  const listeners = new Map<string, Set<EventHandler<unknown>>>();

  return {
    on<K extends keyof EventMap>(event: K, handler: EventHandler<EventMap[K]>) {
      if (!listeners.has(event)) listeners.set(event, new Set());
      const set = listeners.get(event)!;
      set.add(handler as EventHandler<unknown>);
      return () => { set.delete(handler as EventHandler<unknown>); };
    },
    emit<K extends keyof EventMap>(event: K, data: EventMap[K]) {
      const set = listeners.get(event);
      if (set) set.forEach((h) => h(data));
    },
  };
}
