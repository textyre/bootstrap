import mitt from 'mitt';
import type { AppEvents } from '../types/auth.types';

export const bus = mitt<AppEvents>();
