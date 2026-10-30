import assert from "node:assert/strict";
import {describe, it} from "node:test";

import {
  confirmPasswordReset,
  PasswordResetDependencies,
  PasswordResetPublicError,
  requestPasswordReset,
  verifyPasswordResetCode,
} from "./passwordReset";
import {
  consumeEmailDailyCounters,
  DailyCounterState,
} from "./rateLimit";

function fixture(options: {
  account?: "password" | "google" | "unknown";
  allowed?: boolean;
  dailyEmailAllowed?: boolean;
} = {}) {
  let now = 1_000_000;
  let record: Awaited<ReturnType<PasswordResetDependencies["getRecord"]>> = null;
  const sent: Array<{email: string; code: string}> = [];
  const passwords: string[] = [];
  let revocations = 0;
  const account = options.account ?? "password";
  const deps: PasswordResetDependencies = {
    lookupAccount: async () => account === "unknown" ? null : {
      localId: "uid-1",
      hasPassword: account === "password",
    },
    getRecord: async () => record,
    setRecord: async (_, value) => { record = {...value}; },
    deleteRecord: async () => { record = null; },
    updatePassword: async (_, password) => { passwords.push(password); },
    revokeRefreshTokens: async () => { revocations++; },
    sendCode: async (email, code) => { sent.push({email, code}); },
    allowRequest: async () => options.allowed ?? true,
    allowDailyEmail: async () => options.dailyEmailAllowed ?? true,
    acquireLock: async () => true,
    releaseLock: async () => undefined,
    hmacSecret: "test-secret",
    now: () => now,
    generateCode: () => "123456",
    generateToken: () => "single-use-token",
  };
  return {
    deps,
    sent,
    passwords,
    get revocations() { return revocations; },
    get record() { return record; },
    advance(milliseconds: number) { now += milliseconds; },
  };
}

async function expectPublicError(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error) =>
    error instanceof PasswordResetPublicError && error.code === code,
  );
}

describe("password reset", () => {
  it("returns the same request response for password, unknown, Google-only, and limited emails", async () => {
    const results = [];
    for (const options of [
      {account: "password" as const},
      {account: "unknown" as const},
      {account: "google" as const},
      {account: "password" as const, allowed: false},
    ]) {
      const item = fixture(options);
      results.push(await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1"));
    }
    assert.deepEqual(results, [{ok: true}, {ok: true}, {ok: true}, {ok: true}]);
  });

  it("does not send to unknown, Google-only, or rate-limited accounts", async () => {
    for (const options of [
      {account: "unknown" as const},
      {account: "google" as const},
      {account: "password" as const, allowed: false},
    ]) {
      const item = fixture(options);
      await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1");
      assert.equal(item.sent.length, 0);
    }
  });

  it("keeps the neutral response and skips a daily-capped email", async () => {
    const allowed = fixture();
    const capped = fixture({dailyEmailAllowed: false});
    const allowedResponse = await requestPasswordReset(
      allowed.deps,
      "person@example.com",
      "127.0.0.1",
    );
    const cappedResponse = await requestPasswordReset(
      capped.deps,
      "person@example.com",
      "127.0.0.1",
    );
    assert.deepEqual(cappedResponse, allowedResponse);
    assert.deepEqual(cappedResponse, {ok: true});
    assert.equal(allowed.sent.length, 1);
    assert.equal(capped.sent.length, 0);
  });

  it("skips the sixth recipient email with identical neutral responses", async () => {
    const item = fixture();
    let global: DailyCounterState | undefined;
    let recipient: DailyCounterState | undefined;
    item.deps.allowDailyEmail = async () => {
      const outcome = consumeEmailDailyCounters(
        global,
        recipient,
        Date.UTC(2026, 9, 30, 4),
      );
      if (!outcome.ok) return false;
      global = outcome.global;
      recipient = outcome.scoped;
      return true;
    };

    const responses = [];
    for (let request = 0; request < 6; request++) {
      responses.push(await requestPasswordReset(
        item.deps,
        "person@example.com",
        "127.0.0.1",
      ));
      item.advance(30_001);
    }
    assert.deepEqual(responses, Array(6).fill({ok: true}));
    assert.equal(item.sent.length, 5);
  });

  it("skips the 101st global email with identical neutral responses", async () => {
    const item = fixture();
    let global: DailyCounterState | undefined;
    const recipients = new Map<string, DailyCounterState>();
    item.deps.allowDailyEmail = async (email) => {
      const outcome = consumeEmailDailyCounters(
        global,
        recipients.get(email),
        Date.UTC(2026, 9, 30, 4),
      );
      if (!outcome.ok) return false;
      global = outcome.global;
      recipients.set(email, outcome.scoped!);
      return true;
    };

    const responses = [];
    for (let request = 0; request < 101; request++) {
      responses.push(await requestPasswordReset(
        item.deps,
        `person${request}@example.com`,
        "127.0.0.1",
      ));
      item.advance(30_001);
    }
    assert.deepEqual(responses, Array(101).fill({ok: true}));
    assert.equal(item.sent.length, 100);
  });

  it("expires a code after ten minutes", async () => {
    const item = fixture();
    await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1");
    item.advance(10 * 60 * 1000 + 1);
    await expectPublicError(
      verifyPasswordResetCode(item.deps, "person@example.com", "123456"),
      "invalid_code",
    );
    assert.equal(item.record, null);
  });

  it("burns the code after five wrong attempts", async () => {
    const item = fixture();
    await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1");
    for (let attempt = 0; attempt < 5; attempt++) {
      await expectPublicError(
        verifyPasswordResetCode(item.deps, "person@example.com", "000000"),
        "invalid_code",
      );
    }
    assert.equal(item.record, null);
  });

  it("makes the code and reset token single use", async () => {
    const item = fixture();
    await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1");
    const verified = await verifyPasswordResetCode(
      item.deps,
      "person@example.com",
      "123456",
    );
    await expectPublicError(
      verifyPasswordResetCode(item.deps, "person@example.com", "123456"),
      "invalid_code",
    );
    await confirmPasswordReset(
      item.deps,
      "person@example.com",
      verified.resetToken,
      "new-pass-123",
    );
    await expectPublicError(
      confirmPasswordReset(
        item.deps,
        "person@example.com",
        verified.resetToken,
        "new-pass-123",
      ),
      "invalid_token",
    );
  });

  it("enforces eight characters and revokes refresh tokens after updating", async () => {
    const item = fixture();
    await requestPasswordReset(item.deps, "person@example.com", "127.0.0.1");
    const verified = await verifyPasswordResetCode(
      item.deps,
      "person@example.com",
      "123456",
    );
    await expectPublicError(
      confirmPasswordReset(item.deps, "person@example.com", verified.resetToken, "short"),
      "weak_password",
    );
    await confirmPasswordReset(
      item.deps,
      "person@example.com",
      verified.resetToken,
      "long-enough",
    );
    assert.deepEqual(item.passwords, ["long-enough"]);
    assert.equal(item.revocations, 1);
  });

  it("does not log sensitive request values", async () => {
    const item = fixture();
    item.deps.lookupAccount = async () => { throw new Error("provider unavailable"); };
    const original = console.error;
    const logged: unknown[][] = [];
    console.error = (...values: unknown[]) => { logged.push(values); };
    try {
      await requestPasswordReset(item.deps, "private@example.com", "127.0.0.1");
    } finally {
      console.error = original;
    }
    assert.deepEqual(logged, []);
  });
});
