import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {ApiError} from "./errors";
import {
  consumeFixedWindow,
  consumeEmailDailyCounters,
  consumeProtectedDailyCounters,
  DailyCounterState,
  manilaDailyWindow,
  nextRateBucket,
  RATE_LIMIT_CONFIG,
  RATE_LIMITS,
  WINDOW_MS,
} from "./rateLimit";

describe("nextRateBucket over-limit", () => {
  it("throws ApiError 429 when count reaches the limit", () => {
    const limit = RATE_LIMITS.rateLimitTest;
    let state = nextRateBucket(undefined, limit, 1000);
    for (let i = 1; i < limit; i++) {
      state = nextRateBucket(state, limit, 1000 + i);
    }
    assert.equal(state.count, limit);
    assert.throws(
      () => nextRateBucket(state, limit, 1000 + limit),
      (error: unknown) =>
        error instanceof ApiError && error.status === 429,
    );
  });

  it("resets after the window so a new request is allowed", () => {
    const next = nextRateBucket(
      {count: 5, windowStart: 1000},
      5,
      1000 + WINDOW_MS,
    );
    assert.equal(next.count, 1);
  });
});

describe("daily limits", () => {
  const midday = Date.UTC(2026, 9, 30, 4, 0, 0);

  it("blocks a user's 151st action without affecting another user", () => {
    let global: DailyCounterState | undefined;
    let firstUser: DailyCounterState | undefined;
    for (
      let count = 0;
      count < RATE_LIMIT_CONFIG.daily.protectedActionsPerUser;
      count++
    ) {
      const outcome = consumeProtectedDailyCounters(
        global,
        firstUser,
        midday,
      );
      assert.equal(outcome.ok, true);
      if (!outcome.ok) return;
      global = outcome.global;
      firstUser = outcome.scoped;
    }

    const blocked = consumeProtectedDailyCounters(global, firstUser, midday);
    assert.equal(blocked.ok, false);
    if (blocked.ok) return;
    assert.equal(blocked.status, 429);
    assert.equal(blocked.info.count, 150);

    const otherUser = consumeProtectedDailyCounters(global, undefined, midday);
    assert.equal(otherUser.ok, true);
  });

  it("returns 503 at the global valve without incrementing rejected requests", () => {
    const expiresAt = manilaDailyWindow(midday).expiresAt;
    const atLimit = {
      count: RATE_LIMIT_CONFIG.daily.protectedRequestsGlobal,
      expiresAt,
    };
    const first = consumeProtectedDailyCounters(atLimit, undefined, midday);
    const second = consumeProtectedDailyCounters(atLimit, undefined, midday);
    assert.equal(first.ok, false);
    assert.equal(second.ok, false);
    if (first.ok || second.ok) return;
    assert.equal(first.status, 503);
    assert.equal(first.code, "temporarily-busy");
    assert.equal(first.info.count, 20_000);
    assert.equal(second.info.count, 20_000);
  });

  it("blocks the sixth recipient email and the 101st global email", () => {
    let global: DailyCounterState | undefined;
    let recipient: DailyCounterState | undefined;
    for (let count = 0; count < 5; count++) {
      const outcome = consumeEmailDailyCounters(global, recipient, midday);
      assert.equal(outcome.ok, true);
      if (!outcome.ok) return;
      global = outcome.global;
      recipient = outcome.scoped;
    }
    const sixth = consumeEmailDailyCounters(global, recipient, midday);
    assert.equal(sixth.ok, false);
    if (!sixth.ok) assert.equal(sixth.info.bucket, "dailyEmailRecipient");

    const expiresAt = manilaDailyWindow(midday).expiresAt;
    const globalLimit = consumeEmailDailyCounters(
      {count: 100, expiresAt},
      undefined,
      midday,
    );
    assert.equal(globalLimit.ok, false);
    if (!globalLimit.ok) {
      assert.equal(globalLimit.info.bucket, "dailyEmailGlobal");
      assert.equal(globalLimit.info.count, 100);
    }
  });

  it("rolls over at midnight Asia/Manila", () => {
    const before = Date.UTC(2026, 9, 30, 15, 59, 59, 999);
    const after = Date.UTC(2026, 9, 30, 16, 0, 0, 0);
    assert.equal(manilaDailyWindow(before).key, "2026-10-30");
    assert.equal(manilaDailyWindow(after).key, "2026-10-31");
    assert.equal(manilaDailyWindow(before).resetAt, after);

    const freshDay = consumeProtectedDailyCounters(undefined, undefined, after);
    assert.equal(freshDay.ok, true);
    if (freshDay.ok) assert.equal(freshDay.scoped?.count, 1);
  });
});

describe("password reset fixed-window limits", () => {
  it("allows three requests per hour and rejects the fourth", () => {
    const hour = 60 * 60 * 1000;
    let state;
    for (let count = 0; count < 3; count++) {
      const outcome = consumeFixedWindow(state, 3, hour, 1000 + count);
      assert.equal(outcome.allowed, true);
      state = outcome.state;
    }
    assert.equal(consumeFixedWindow(state, 3, hour, 2000).allowed, false);
    assert.equal(
      consumeFixedWindow(state, 3, hour, hour + 1000).allowed,
      true,
    );
  });
});
