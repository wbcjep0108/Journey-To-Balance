import {
  DocumentData,
  FieldValue,
  getFirestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  adjustRemaining,
  budgetToFirestore,
  BudgetState,
  CategoryKey,
  distributeAddedFunds,
  isCategory,
  migrateBudgetSchemaIfNeeded,
  parseBudget,
  reallocateAllFromAvailableBalance,
  remainingFor,
  SAVINGS_GOAL_ENTRY_TITLE,
} from "./budgetMath.js";
import {
  failedPrecondition,
  invalidArgument,
  notFound,
} from "./errors.js";
import {RATE_LIMITS, RateBucketName} from "./rateLimit.js";
import {
  enforceRateLimits,
  idempotencyRef,
} from "./security.js";

const EPS = 0.001;

function userRef(uid: string) {
  return getFirestore().collection("users").doc(uid);
}

function entryRef(uid: string, category: CategoryKey, entryId: string) {
  return userRef(uid).collection(category).doc(entryId);
}

function readBudgetFromUserData(data: DocumentData | undefined): BudgetState {
  const budget = parseBudget(data?.budget);
  migrateBudgetSchemaIfNeeded(budget);
  return budget;
}

function writeBudget(
  tx: Transaction,
  uid: string,
  budget: BudgetState,
): void {
  const payload = budgetToFirestore(budget);
  payload.updatedAt = FieldValue.serverTimestamp();
  tx.set(userRef(uid), {budget: payload}, {merge: true});
}

async function withIdempotency<T extends Record<string, unknown>>(
  uid: string,
  requestId: string | undefined,
  bucket: RateBucketName,
  run: () => Promise<T>,
): Promise<T> {
  if (requestId != null && typeof requestId === "string") {
    const trimmed = requestId.trim();
    if (trimmed.length < 8 || trimmed.length > 128) {
      throw invalidArgument("Invalid requestId.");
    }
    const ref = idempotencyRef(uid, trimmed);
    const existing = await ref.get();
    if (existing.exists) {
      return existing.data()?.result as T;
    }

    await enforceRateLimits(uid, bucket);
    const result = await run();
    await ref.set({
      result,
      bucket,
      createdAt: FieldValue.serverTimestamp(),
    });
    return result;
  }

  await enforceRateLimits(uid, bucket);
  return run();
}

function requirePositiveAmount(amount: unknown): number {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    throw invalidArgument("Amount must be greater than zero.");
  }
  return amount;
}

function requireNonNegative(amount: unknown, label: string): number {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount < 0) {
    throw invalidArgument(`${label} cannot be negative.`);
  }
  return amount;
}

function validatePercentages(
  bills: number,
  savings: number,
  personal: number,
): void {
  const total = bills + savings + personal;
  if (Math.abs(total - 100) > EPS) {
    throw invalidArgument("Budget percentages must total 100.");
  }
  if (bills < 0 || savings < 0 || personal < 0) {
    throw invalidArgument("Percentages cannot be negative.");
  }
}

export async function receiveSalaryOp(
  uid: string,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  return withIdempotency(uid, requestId, "receiveSalary", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(snap.data());
      if (budget.monthlySalary <= 0) {
        throw failedPrecondition(
          "Set a monthly salary before receiving it.",
        );
      }
      budget.availableBalance += budget.monthlySalary;
      distributeAddedFunds(budget, budget.monthlySalary);
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget)};
    });
  });
}

export async function addMoneyOp(
  uid: string,
  amountRaw: unknown,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  const amount = requirePositiveAmount(amountRaw);
  return withIdempotency(uid, requestId, "addMoney", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(snap.data());
      budget.availableBalance += amount;
      distributeAddedFunds(budget, amount);
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget)};
    });
  });
}

export async function updateAvailableBalanceOp(
  uid: string,
  newBalanceRaw: unknown,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  const newBalance = requireNonNegative(newBalanceRaw, "Available balance");
  return withIdempotency(
    uid,
    requestId,
    "updateAvailableBalance",
    async () => {
      return getFirestore().runTransaction(async (tx) => {
        const snap = await tx.get(userRef(uid));
        const budget = readBudgetFromUserData(snap.data());
        budget.availableBalance = newBalance;
        reallocateAllFromAvailableBalance(budget);
        writeBudget(tx, uid, budget);
        return {budget: budgetToFirestore(budget)};
      });
    },
  );
}

export async function updatePercentagesOp(
  uid: string,
  billsRaw: unknown,
  savingsRaw: unknown,
  personalRaw: unknown,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  const billsPercentage = requireNonNegative(billsRaw, "Bills percentage");
  const savingsPercentage = requireNonNegative(
    savingsRaw,
    "Savings percentage",
  );
  const personalPercentage = requireNonNegative(
    personalRaw,
    "Personal percentage",
  );
  validatePercentages(billsPercentage, savingsPercentage, personalPercentage);

  return withIdempotency(uid, requestId, "updatePercentages", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(snap.data());
      budget.billsPercentage = billsPercentage;
      budget.savingsPercentage = savingsPercentage;
      budget.personalPercentage = personalPercentage;
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget)};
    });
  });
}

export async function updateMonthlySalaryOp(
  uid: string,
  salaryRaw: unknown,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  const monthlySalary = requireNonNegative(salaryRaw, "Monthly salary");
  return withIdempotency(uid, requestId, "updateMonthlySalary", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(snap.data());
      budget.monthlySalary = monthlySalary;
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget)};
    });
  });
}

export async function addTransactionOp(
  uid: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const category = data.category;
  if (!isCategory(category)) {
    throw invalidArgument("Invalid category.");
  }
  const title = typeof data.title === "string" ? data.title.trim() : "";
  if (!title) {
    throw invalidArgument("Title is required.");
  }
  const amount = requirePositiveAmount(data.amount);
  const entryId = typeof data.entryId === "string" ? data.entryId.trim() : "";
  if (!entryId || entryId.length > 128) {
    throw invalidArgument("Invalid entryId.");
  }
  const requestId = data.requestId as string | undefined;
  const createdAtMs = typeof data.createdAtMs === "number" ?
    data.createdAtMs :
    Date.now();

  return withIdempotency(uid, requestId, "addTransaction", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(userSnap.data());
      const available = remainingFor(budget, category);
      if (amount > available + EPS) {
        throw failedPrecondition(
          "Amount exceeds the available category balance.",
        );
      }

      const eRef = entryRef(uid, category, entryId);
      const existing = await tx.get(eRef);
      if (existing.exists) {
        // Idempotent replay via entry id.
        return {budget: budgetToFirestore(budget), entryId};
      }

      budget.availableBalance = Math.max(0, budget.availableBalance - amount);
      adjustRemaining(budget, category, -amount);

      tx.set(eRef, {
        title,
        amount,
        createdAt: Timestamp.fromMillis(createdAtMs),
        isRefund: false,
      });
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget), entryId};
    });
  });
}

export async function updateTransactionOp(
  uid: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const category = data.category;
  if (!isCategory(category)) {
    throw invalidArgument("Invalid category.");
  }
  const entryId = typeof data.entryId === "string" ? data.entryId.trim() : "";
  if (!entryId) {
    throw invalidArgument("Invalid entryId.");
  }
  const title = typeof data.title === "string" ? data.title.trim() : "";
  if (!title) {
    throw invalidArgument("Title is required.");
  }
  const amount = requirePositiveAmount(data.amount);
  const requestId = data.requestId as string | undefined;

  return withIdempotency(uid, requestId, "updateTransaction", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(userSnap.data());
      const eRef = entryRef(uid, category, entryId);
      const entrySnap = await tx.get(eRef);
      if (!entrySnap.exists) {
        throw notFound("Transaction not found.");
      }
      const previous = entrySnap.data() ?? {};
      if (previous.isRefund === true) {
        throw failedPrecondition("Refunded transactions cannot be edited.");
      }
      const previousAmount = typeof previous.amount === "number" ?
        previous.amount :
        0;
      const delta = amount - previousAmount;
      const availableForEdit =
        remainingFor(budget, category) + previousAmount;
      if (amount > availableForEdit + EPS) {
        throw failedPrecondition(
          "Amount exceeds the available category balance.",
        );
      }

      budget.availableBalance = Math.max(
        0,
        budget.availableBalance - delta,
      );
      adjustRemaining(budget, category, -delta);

      tx.set(eRef, {
        title,
        amount,
        createdAt: previous.createdAt ?? Timestamp.now(),
        isRefund: false,
      }, {merge: true});
      writeBudget(tx, uid, budget);
      return {budget: budgetToFirestore(budget), entryId};
    });
  });
}

export async function deleteTransactionOp(
  uid: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const category = data.category;
  if (!isCategory(category)) {
    throw invalidArgument("Invalid category.");
  }
  const entryId = typeof data.entryId === "string" ? data.entryId.trim() : "";
  if (!entryId) {
    throw invalidArgument("Invalid entryId.");
  }
  const refund = data.refund !== false;
  const requestId = data.requestId as string | undefined;

  return withIdempotency(uid, requestId, "deleteTransaction", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef(uid));
      const budget = readBudgetFromUserData(userSnap.data());
      const eRef = entryRef(uid, category, entryId);
      const entrySnap = await tx.get(eRef);
      if (!entrySnap.exists) {
        // Already gone — idempotent success.
        return {budget: budgetToFirestore(budget), deleted: true, refunded: false};
      }
      const entry = entrySnap.data() ?? {};
      const amount = typeof entry.amount === "number" ? entry.amount : 0;
      const isRefund = entry.isRefund === true;
      const isGoal = entry.title === SAVINGS_GOAL_ENTRY_TITLE;
      const shouldRefund = refund && !isRefund;

      if (shouldRefund) {
        budget.availableBalance += amount;
        adjustRemaining(budget, category, amount);
        if (isGoal) {
          budget.savingsGoalCurrent = Math.max(
            0,
            budget.savingsGoalCurrent - amount,
          );
        }
        tx.set(eRef, {
          ...entry,
          isRefund: true,
        }, {merge: true});
        writeBudget(tx, uid, budget);
        return {
          budget: budgetToFirestore(budget),
          deleted: false,
          refunded: true,
        };
      }

      tx.delete(eRef);
      writeBudget(tx, uid, budget);
      return {
        budget: budgetToFirestore(budget),
        deleted: true,
        refunded: false,
      };
    });
  });
}

export async function contributeToSavingsGoalOp(
  uid: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const source = data.source;
  if (!isCategory(source)) {
    throw invalidArgument("Invalid source category.");
  }
  const amount = requirePositiveAmount(data.amount);
  const entryId = typeof data.entryId === "string" ? data.entryId.trim() : "";
  if (!entryId) {
    throw invalidArgument("Invalid entryId.");
  }
  const requestId = data.requestId as string | undefined;
  const createdAtMs = typeof data.createdAtMs === "number" ?
    data.createdAtMs :
    Date.now();

  return withIdempotency(
    uid,
    requestId,
    "contributeToSavingsGoal",
    async () => {
      return getFirestore().runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef(uid));
        const budget = readBudgetFromUserData(userSnap.data());
        if (amount > remainingFor(budget, source) + EPS) {
          throw failedPrecondition(
            "Amount exceeds the available category balance.",
          );
        }

        const eRef = entryRef(uid, source, entryId);
        const existing = await tx.get(eRef);
        if (existing.exists) {
          return {budget: budgetToFirestore(budget), entryId};
        }

        budget.availableBalance = Math.max(
          0,
          budget.availableBalance - amount,
        );
        adjustRemaining(budget, source, -amount);
        budget.savingsGoalCurrent += amount;

        tx.set(eRef, {
          title: SAVINGS_GOAL_ENTRY_TITLE,
          amount,
          createdAt: Timestamp.fromMillis(createdAtMs),
          isRefund: false,
        });
        writeBudget(tx, uid, budget);
        return {budget: budgetToFirestore(budget), entryId};
      });
    },
  );
}

export async function updateSavingsGoalSettingsOp(
  uid: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const target = requirePositiveAmount(data.target);
  const targetDateMs = typeof data.targetDateMs === "number" ?
    data.targetDateMs :
    NaN;
  if (!Number.isFinite(targetDateMs)) {
    throw invalidArgument("Invalid target date.");
  }
  const titleRaw = typeof data.title === "string" ? data.title.trim() : "";
  if (!titleRaw) {
    throw invalidArgument("Goal title cannot be empty.");
  }
  const requestId = data.requestId as string | undefined;

  return withIdempotency(
    uid,
    requestId,
    "updateSavingsGoalSettings",
    async () => {
      return getFirestore().runTransaction(async (tx) => {
        const snap = await tx.get(userRef(uid));
        const budget = readBudgetFromUserData(snap.data());
        budget.savingsGoalTarget = target;
        budget.savingsGoalTargetDateMs = targetDateMs;
        budget.savingsGoalTitle = titleRaw;
        writeBudget(tx, uid, budget);
        return {budget: budgetToFirestore(budget)};
      });
    },
  );
}

export async function migrateBudgetSchemaOp(
  uid: string,
  requestId: string | undefined,
): Promise<Record<string, unknown>> {
  return withIdempotency(uid, requestId, "migrateBudgetSchema", async () => {
    return getFirestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef(uid));
      const budget = parseBudget(snap.data()?.budget);
      const migrated = migrateBudgetSchemaIfNeeded(budget);
      if (migrated) {
        writeBudget(tx, uid, budget);
      }
      return {budget: budgetToFirestore(budget), migrated};
    });
  });
}

/** Re-export limits for docs/tests. */
export {RATE_LIMITS};

export function mapUnknownError(error: unknown): never {
  if (error instanceof HttpsError) {
    throw error;
  }
  console.error("Finance operation failed", error);
  throw new HttpsError("internal", "Unexpected server error.");
}
