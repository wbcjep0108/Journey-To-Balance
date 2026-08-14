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
} from "./budgetMath";
import {
  badRequest,
  conflict,
  internal,
  notFound,
  RateLimitExceededError,
} from "./errors";
import {FirestoreClient} from "./firestore";
import {RATE_LIMITS, RateBucketName} from "./rateLimit";
import type {UserGate} from "./UserGate";

const EPS = 0.001;

export type Env = {
  USER_GATE: DurableObjectNamespace<UserGate>;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
};

function requirePositiveAmount(amount: unknown): number {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    throw badRequest("Amount must be greater than zero.");
  }
  return amount;
}

function requireNonNegative(amount: unknown, label: string): number {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount < 0) {
    throw badRequest(`${label} cannot be negative.`);
  }
  return amount;
}

function validatePercentages(bills: number, savings: number, personal: number): void {
  if (Math.abs(bills + savings + personal - 100) > EPS) {
    throw badRequest("Budget percentages must total 100.");
  }
  if (bills < 0 || savings < 0 || personal < 0) {
    throw badRequest("Percentages cannot be negative.");
  }
}

function normalizeRequestId(requestId: unknown): string | undefined {
  if (requestId == null) return undefined;
  if (typeof requestId !== "string") {
    throw badRequest("Invalid requestId.");
  }
  const trimmed = requestId.trim();
  if (trimmed.length < 8 || trimmed.length > 128) {
    throw badRequest("Invalid requestId.");
  }
  return trimmed;
}

/** Optional category icon asset path from the Flutter client. */
function normalizeIconAsset(value: unknown): string | undefined {
  if (value == null) return undefined;
  if (typeof value !== "string") {
    throw badRequest("Invalid iconAsset.");
  }
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  if (trimmed.length > 200) {
    throw badRequest("Invalid iconAsset.");
  }
  if (!trimmed.startsWith("assets/images/icons_")) {
    return undefined;
  }
  return trimmed;
}

function loadBudget(userDoc: Record<string, unknown> | null): BudgetState {
  const budget = parseBudget(userDoc?.budget);
  migrateBudgetSchemaIfNeeded(budget);
  return budget;
}

function gateFor(env: Env, uid: string): DurableObjectStub<UserGate> {
  return env.USER_GATE.get(env.USER_GATE.idFromName(uid));
}

async function withProtection<T>(
  env: Env,
  uid: string,
  bucket: RateBucketName,
  requestId: string | undefined,
  run: () => Promise<T>,
): Promise<T> {
  const gate = gateFor(env, uid);

  if (requestId) {
    const existing = await gate.getIdempotency(requestId);
    if (existing != null) {
      return existing as T;
    }
  }

  // Structured DO outcome (same as /api/test/rate-limit-add-money).
  // Never throw ApiError across DO RPC — instanceof is lost → HTTP 500.
  const outcome = await gate.enforceRateLimitsOutcome(bucket);
  if (!outcome.ok) {
    throw new RateLimitExceededError(
      {
        bucket: outcome.info.bucket,
        limit: outcome.info.limit,
        remaining: outcome.info.remaining,
        resetAt: outcome.info.resetAt,
      },
      outcome.message,
    );
  }

  const result = await run();

  if (requestId) {
    await gate.saveIdempotency(requestId, result);
  }
  return result;
}

function db(env: Env): FirestoreClient {
  if (!env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw internal(
      "Server misconfigured: FIREBASE_SERVICE_ACCOUNT_JSON is not set.",
    );
  }
  return new FirestoreClient(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT_JSON);
}

async function saveBudget(
  client: FirestoreClient,
  uid: string,
  budget: BudgetState,
  entry?: {category: CategoryKey; entryId: string; data: Record<string, unknown>},
  deleteEntry?: {category: CategoryKey; entryId: string},
): Promise<Record<string, unknown>> {
  const payload = budgetToFirestore(budget);
  payload.updatedAt = new Date().toISOString();
  await client.commitUserBudget({
    uid,
    budget: payload,
    entry: entry ?
      {
        category: entry.category,
        entryId: entry.entryId,
        data: entry.data,
      } :
      undefined,
    deleteEntry: deleteEntry ?
      {
        category: deleteEntry.category,
        entryId: deleteEntry.entryId,
      } :
      undefined,
  });
  return {budget: payload};
}

export async function handleFinance(
  env: Env,
  uid: string,
  route: string,
  body: Record<string, unknown>,
): Promise<unknown> {
  const client = db(env);
  const requestId = normalizeRequestId(body.requestId);

  switch (route) {
  case "receive-salary":
    return withProtection(env, uid, "receiveSalary", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      if (budget.monthlySalary <= 0) {
        throw conflict("Set a monthly salary before receiving it.");
      }
      budget.availableBalance += budget.monthlySalary;
      distributeAddedFunds(budget, budget.monthlySalary);
      return saveBudget(client, uid, budget);
    });

  case "add-money": {
    const amount = requirePositiveAmount(body.amount);
    return withProtection(env, uid, "addMoney", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      budget.availableBalance += amount;
      distributeAddedFunds(budget, amount);
      return saveBudget(client, uid, budget);
    });
  }

  case "update-available-balance": {
    const availableBalance = requireNonNegative(
      body.availableBalance,
      "Available balance",
    );
    return withProtection(
      env,
      uid,
      "updateAvailableBalance",
      requestId,
      async () => {
        const userDoc = await client.getUserDoc(uid);
        const budget = loadBudget(userDoc);
        budget.availableBalance = availableBalance;
        reallocateAllFromAvailableBalance(budget);
        return saveBudget(client, uid, budget);
      },
    );
  }

  case "update-percentages": {
    const billsPercentage = requireNonNegative(body.billsPercentage, "Bills percentage");
    const savingsPercentage = requireNonNegative(
      body.savingsPercentage,
      "Savings percentage",
    );
    const personalPercentage = requireNonNegative(
      body.personalPercentage,
      "Personal percentage",
    );
    validatePercentages(billsPercentage, savingsPercentage, personalPercentage);
    return withProtection(env, uid, "updatePercentages", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      budget.billsPercentage = billsPercentage;
      budget.savingsPercentage = savingsPercentage;
      budget.personalPercentage = personalPercentage;
      return saveBudget(client, uid, budget);
    });
  }

  case "update-monthly-salary": {
    const monthlySalary = requireNonNegative(body.monthlySalary, "Monthly salary");
    return withProtection(env, uid, "updateMonthlySalary", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      budget.monthlySalary = monthlySalary;
      return saveBudget(client, uid, budget);
    });
  }

  case "add-transaction": {
    if (!isCategory(body.category)) throw badRequest("Invalid category.");
    const category = body.category;
    const title = typeof body.title === "string" ? body.title.trim() : "";
    if (!title) throw badRequest("Title is required.");
    const amount = requirePositiveAmount(body.amount);
    const entryId = typeof body.entryId === "string" ? body.entryId.trim() : "";
    if (!entryId || entryId.length > 128) throw badRequest("Invalid entryId.");
    const createdAtMs =
      typeof body.createdAtMs === "number" ? body.createdAtMs : Date.now();
    const iconAsset = normalizeIconAsset(body.iconAsset);

    return withProtection(env, uid, "addTransaction", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      if (amount > remainingFor(budget, category) + EPS) {
        throw conflict("Amount exceeds the available category balance.");
      }
      const existing = await client.getEntry(uid, category, entryId);
      if (existing) {
        return {budget: budgetToFirestore(budget), entryId};
      }
      budget.availableBalance = Math.max(0, budget.availableBalance - amount);
      adjustRemaining(budget, category, -amount);
      return saveBudget(client, uid, budget, {
        category,
        entryId,
        data: {
          title,
          amount,
          createdAt: new Date(createdAtMs),
          isRefund: false,
          ...(iconAsset ? {iconAsset} : {}),
        },
      }).then((result) => ({...result, entryId}));
    });
  }

  case "update-transaction": {
    if (!isCategory(body.category)) throw badRequest("Invalid category.");
    const category = body.category;
    const entryId = typeof body.entryId === "string" ? body.entryId.trim() : "";
    if (!entryId) throw badRequest("Invalid entryId.");
    const title = typeof body.title === "string" ? body.title.trim() : "";
    if (!title) throw badRequest("Title is required.");
    const amount = requirePositiveAmount(body.amount);
    const iconAsset = normalizeIconAsset(body.iconAsset);

    return withProtection(env, uid, "updateTransaction", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      const previous = await client.getEntry(uid, category, entryId);
      if (!previous) throw notFound("Transaction not found.");
      if (previous.isRefund === true) {
        throw conflict("Refunded transactions cannot be edited.");
      }
      const previousAmount =
        typeof previous.amount === "number" ? previous.amount : 0;
      const delta = amount - previousAmount;
      const availableForEdit = remainingFor(budget, category) + previousAmount;
      if (amount > availableForEdit + EPS) {
        throw conflict("Amount exceeds the available category balance.");
      }
      budget.availableBalance = Math.max(0, budget.availableBalance - delta);
      adjustRemaining(budget, category, -delta);
      const previousCreatedAt =
        typeof previous.createdAt === "string" ?
          new Date(previous.createdAt) :
          new Date();
      const previousIcon =
        typeof previous.iconAsset === "string" ?
          normalizeIconAsset(previous.iconAsset) :
          undefined;
      const nextIcon = iconAsset ?? previousIcon;
      return saveBudget(client, uid, budget, {
        category,
        entryId,
        data: {
          title,
          amount,
          createdAt: previousCreatedAt,
          isRefund: false,
          ...(nextIcon ? {iconAsset: nextIcon} : {}),
        },
      }).then((result) => ({...result, entryId}));
    });
  }

  case "delete-transaction": {
    if (!isCategory(body.category)) throw badRequest("Invalid category.");
    const category = body.category;
    const entryId = typeof body.entryId === "string" ? body.entryId.trim() : "";
    if (!entryId) throw badRequest("Invalid entryId.");
    const refund = body.refund !== false;

    return withProtection(env, uid, "deleteTransaction", requestId, async () => {
      const userDoc = await client.getUserDoc(uid);
      const budget = loadBudget(userDoc);
      const entry = await client.getEntry(uid, category, entryId);
      if (!entry) {
        return {budget: budgetToFirestore(budget), deleted: true, refunded: false};
      }
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
        const createdAt =
          typeof entry.createdAt === "string" ?
            new Date(entry.createdAt) :
            new Date();
        return saveBudget(client, uid, budget, {
          category,
          entryId,
          data: {
            title: entry.title ?? "",
            amount,
            createdAt,
            isRefund: true,
            ...(typeof entry.iconAsset === "string" &&
            entry.iconAsset.trim().startsWith("assets/images/icons_") ?
              {iconAsset: entry.iconAsset.trim()} :
              {}),
          },
        }).then((result) => ({
          ...result,
          deleted: false,
          refunded: true,
        }));
      }

      return saveBudget(client, uid, budget, undefined, {
        category,
        entryId,
      }).then((result) => ({
        ...result,
        deleted: true,
        refunded: false,
      }));
    });
  }

  case "contribute-to-savings-goal": {
    if (!isCategory(body.source)) throw badRequest("Invalid source category.");
    const source = body.source;
    const amount = requirePositiveAmount(body.amount);
    const entryId = typeof body.entryId === "string" ? body.entryId.trim() : "";
    if (!entryId) throw badRequest("Invalid entryId.");
    const createdAtMs =
      typeof body.createdAtMs === "number" ? body.createdAtMs : Date.now();

    return withProtection(
      env,
      uid,
      "contributeToSavingsGoal",
      requestId,
      async () => {
        const userDoc = await client.getUserDoc(uid);
        const budget = loadBudget(userDoc);
        if (amount > remainingFor(budget, source) + EPS) {
          throw conflict("Amount exceeds the available category balance.");
        }
        const existing = await client.getEntry(uid, source, entryId);
        if (existing) {
          return {budget: budgetToFirestore(budget), entryId};
        }
        budget.availableBalance = Math.max(0, budget.availableBalance - amount);
        adjustRemaining(budget, source, -amount);
        budget.savingsGoalCurrent += amount;
        return saveBudget(client, uid, budget, {
          category: source,
          entryId,
          data: {
            title: SAVINGS_GOAL_ENTRY_TITLE,
            amount,
            createdAt: new Date(createdAtMs),
            isRefund: false,
          },
        }).then((result) => ({...result, entryId}));
      },
    );
  }

  case "update-savings-goal-settings": {
    const target = requirePositiveAmount(body.target);
    const targetDateMs =
      typeof body.targetDateMs === "number" ? body.targetDateMs : NaN;
    if (!Number.isFinite(targetDateMs)) {
      throw badRequest("Invalid target date.");
    }
    const titleRaw = typeof body.title === "string" ? body.title.trim() : "";
    if (!titleRaw) throw badRequest("Goal title cannot be empty.");

    return withProtection(
      env,
      uid,
      "updateSavingsGoalSettings",
      requestId,
      async () => {
        const userDoc = await client.getUserDoc(uid);
        const budget = loadBudget(userDoc);
        budget.savingsGoalTarget = target;
        budget.savingsGoalTargetDateMs = targetDateMs;
        budget.savingsGoalTitle = titleRaw;
        return saveBudget(client, uid, budget);
      },
    );
  }

  case "migrate-budget-schema":
    return withProtection(
      env,
      uid,
      "migrateBudgetSchema",
      requestId,
      async () => {
        const userDoc = await client.getUserDoc(uid);
        const budget = parseBudget(userDoc?.budget);
        const migrated = migrateBudgetSchemaIfNeeded(budget);
        if (!migrated) {
          return {migrated: false, budget: budgetToFirestore(budget)};
        }
        const saved = await saveBudget(client, uid, budget);
        return {...saved, migrated: true};
      },
    );

  default:
    throw notFound(`Unknown finance route: ${route}`);
  }
}

export {RATE_LIMITS};
