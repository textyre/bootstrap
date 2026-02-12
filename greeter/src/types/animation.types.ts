export interface AnimationStep {
  /** CSS selector (ID uses '#', class uses '.') */
  selector: string;
  /** Class to add */
  triggerClass: string;
  /** If true, use standard trigger() which removes boot-pre. If false, only add/remove specified classes. Default: true */
  useTrigger?: boolean;
  /** Classes to remove before adding triggerClass */
  removeClasses?: string[];
  /** Whether to await animationend on this element */
  waitForAnimation?: boolean;
}

export interface AnimationPhase {
  name: string;
  /** Delay before this phase starts (ms) */
  preDelay?: number;
  /** Sequential steps executed in order */
  steps: AnimationStep[];
  /** Steps triggered in parallel at a specific delay offset from phase start */
  parallel?: {
    delay: number;
    steps: AnimationStep[];
  };
  /** Delay after all steps complete */
  postDelay?: number;
}
