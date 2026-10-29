import assert from "node:assert/strict";
import {describe, it} from "node:test";

import type {AuthUser} from "./auth";
import {
  DeleteAccountDependencies,
  handleDeleteAccount,
} from "./deleteAccount";
import {ApiError} from "./errors";

function fixture(nowSeconds = 1_700_000_000) {
  const operations: string[] = [];
  const deps: DeleteAccountDependencies = {
    async purgeFirestoreUserTree(uid: string): Promise<void> {
      operations.push(`purgeFirestore:${uid}`);
    },
    async purgeWorkerState(uid: string): Promise<void> {
      operations.push(`purgeWorker:${uid}`);
    },
    async deleteAuthAccount(uid: string): Promise<void> {
      operations.push(`deleteAuth:${uid}`);
    },
    now: () => nowSeconds * 1000,
  };

  return {deps, operations};
}

describe("deleteAccount", () => {
  it("rejects when token has no auth_time", async () => {
    const {deps} = fixture();
    const user: AuthUser = {
      uid: "user-123",
      email: "test@example.com",
    };

    await assert.rejects(
      handleDeleteAccount(deps, user, {confirmationEmail: "test@example.com"}),
      (err: unknown) => {
        assert(err instanceof ApiError);
        assert.equal(err.status, 401);
        assert.match(err.message, /Fresh authentication required/);
        return true;
      },
    );
  });

  it("rejects when auth_time is older than 5 minutes", async () => {
    const nowSec = 1_700_000_000;
    const {deps} = fixture(nowSec);
    const user: AuthUser = {
      uid: "user-123",
      email: "test@example.com",
      authTime: nowSec - 301, // 301 seconds ago
    };

    await assert.rejects(
      handleDeleteAccount(deps, user, {confirmationEmail: "test@example.com"}),
      (err: unknown) => {
        assert(err instanceof ApiError);
        assert.equal(err.status, 401);
        assert.match(err.message, /Fresh authentication required/);
        return true;
      },
    );
  });

  it("rejects when user has no registered email", async () => {
    const nowSec = 1_700_000_000;
    const {deps} = fixture(nowSec);
    const user: AuthUser = {
      uid: "user-123",
      authTime: nowSec - 10,
    };

    await assert.rejects(
      handleDeleteAccount(deps, user, {confirmationEmail: "test@example.com"}),
      (err: unknown) => {
        assert(err instanceof ApiError);
        assert.equal(err.status, 400);
        assert.match(err.message, /does not have a valid registered email/);
        return true;
      },
    );
  });

  it("rejects when confirmation email does not match", async () => {
    const nowSec = 1_700_000_000;
    const {deps} = fixture(nowSec);
    const user: AuthUser = {
      uid: "user-123",
      email: "test@example.com",
      authTime: nowSec - 10,
    };

    await assert.rejects(
      handleDeleteAccount(deps, user, {confirmationEmail: "wrong@example.com"}),
      (err: unknown) => {
        assert(err instanceof ApiError);
        assert.equal(err.status, 400);
        assert.match(err.message, /does not match/);
        return true;
      },
    );
  });

  it("rejects when confirmation email is empty or missing", async () => {
    const nowSec = 1_700_000_000;
    const {deps} = fixture(nowSec);
    const user: AuthUser = {
      uid: "user-123",
      email: "test@example.com",
      authTime: nowSec - 10,
    };

    await assert.rejects(
      handleDeleteAccount(deps, user, {}),
      (err: unknown) => {
        assert(err instanceof ApiError);
        assert.equal(err.status, 400);
        return true;
      },
    );
  });

  it("successfully purges Firestore, Worker state, and Auth in order when valid", async () => {
    const nowSec = 1_700_000_000;
    const {deps, operations} = fixture(nowSec);
    const user: AuthUser = {
      uid: "user-abc",
      email: "User.Name@Example.COM",
      authTime: nowSec - 60, // 1 minute ago
    };

    const result = await handleDeleteAccount(deps, user, {
      confirmationEmail: "  user.name@example.com  ",
    });

    assert.equal(result.success, true);
    assert.deepEqual(operations, [
      "purgeFirestore:user-abc",
      "purgeWorker:user-abc",
      "deleteAuth:user-abc",
    ]);
  });
});

