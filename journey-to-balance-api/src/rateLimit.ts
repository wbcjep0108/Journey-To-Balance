import {rateLimited} from "./errors";

export const WINDOW_MS = 60_000;

export const RATE_LIMITS = {
  general: 60,
  addTransaction: 30,
  updateAvailableBalance: 20,
  receiveSalary: 5,
  addMoney: 5,
  contributeToSavingsGoal: 20,
  deleteTransaction: 20,
  updatePercentages: 10,
  updateTransaction: 30,
  updateMonthlySalary: 20,
  updateSavingsGoalSettings: 20,
  migrateBudgetSchema: 10,
  /**
   * Isolated non-mutating probe bucket. Does NOT share counters with
   * `general` or any financial operation buckets.
   */
  rateLimitTest: 5,
} as const;

export type RateBucketName = keyof typeof RATE_LIMITS;

export interface RateBucketState {
  count: number;
  windowStart: number;
}

/**
 * Fixed one-minute window counter. Pure helper — no I/O.
 * Throws ApiError(429) when the limit is exceeded.
 */
export function nextRateBucket(
  current: RateBucketState | undefined,
  limit: number,
  now: number,
): RateBucketState {
  if (!current || now - current.windowStart >= WINDOW_MS) {
    return {count: 1, windowStart: now};
  }
  if (current.count >= limit) {
    throw rateLimited();
  }
  return {
    count: current.count + 1,
    windowStart: current.windowStart,
  };
}
