import mitt from 'mitt';
import type { Emitter } from 'mitt';
import type { AppEvents } from '../types/auth.types';

export type IEventBus = Emitter<AppEvents>;

export function createEventBus(): IEventBus {
  return mitt<AppEvents>();
}
