/** Shared budget document shape stored at users/{uid}.budget */

export type CategoryKey = "bills" | "savings" | "personal";

export interface BudgetState {
  availableBalance: number;
  monthlySalary: number;
  billsPercentage: number;
  savingsPercentage: number;
  personalPercentage: number;
  billsRemaining: number;
  savingsRemaining: number;
  personalRemaining: number;
  forfeitedBills: number;
  forfeitedSavings: number;
  forfeitedPersonal: number;
  savingsGoalTarget: number;
  savingsGoalCurrent: number;
  savingsGoalTargetDateMs: number;
  savingsGoalTitle: string;
  schemaVersion: number;
}

export const DEFAULT_GOAL_TITLE = "Saving Goal";
export const SAVINGS_GOAL_ENTRY_TITLE = "Savings Goal";
export const CURRENT_SCHEMA_VERSION = 3;

export const DEFAULT_GOAL_DATE_MS =
  new Date(2028, 11, 31).getTime();

export function num(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

export function parseBudget(raw: unknown): BudgetState {
  const budget = (raw && typeof raw === "object" ? raw : {}) as Record<
    string,
    unknown
  >;

  const availableBalance = num(
    budget.availableBalance ?? budget.income,
    0,
  );
  const billsPercentage = num(budget.billsPercentage, 50);
  const savingsPercentage = num(budget.savingsPercentage, 20);
  const personalPercentage = num(budget.personalPercentage, 30);

  const billsRemaining = budget.billsRemaining == null ?
    availableBalance * (billsPercentage / 100) :
    num(budget.billsRemaining, 0);
  const savingsRemaining = budget.savingsRemaining == null ?
    availableBalance * (savingsPercentage / 100) :
    num(budget.savingsRemaining, 0);
  const personalRemaining = budget.personalRemaining == null ?
    availableBalance * (personalPercentage / 100) :
    num(budget.personalRemaining, 0);

  const title = typeof budget.savingsGoalTitle === "string" ?
    budget.savingsGoalTitle.trim() :
    "";

  return {
    availableBalance,
    monthlySalary: num(
      budget.monthlySalary ?? budget.availableBalance ?? budget.income,
      0,
    ),
    billsPercentage,
    savingsPercentage,
    personalPercentage,
    billsRemaining,
    savingsRemaining,
    personalRemaining,
    forfeitedBills: num(budget.forfeitedBills, 0),
    forfeitedSavings: num(budget.forfeitedSavings, 0),
    forfeitedPersonal: num(budget.forfeitedPersonal, 0),
    savingsGoalTarget: num(budget.savingsGoalTarget, 10000),
    savingsGoalCurrent: num(budget.savingsGoalCurrent, 0),
    savingsGoalTargetDateMs: num(
      budget.savingsGoalTargetDateMs,
      DEFAULT_GOAL_DATE_MS,
    ),
    savingsGoalTitle: title.length > 0 ? title : DEFAULT_GOAL_TITLE,
    schemaVersion: Math.round(num(budget.schemaVersion, 1)),
  };
}

export function budgetToFirestore(budget: BudgetState): Record<string, unknown> {
  return {
    income: budget.availableBalance,
    availableBalance: budget.availableBalance,
    monthlySalary: budget.monthlySalary,
    billsPercentage: budget.billsPercentage,
    savingsPercentage: budget.savingsPercentage,
    personalPercentage: budget.personalPercentage,
    billsRemaining: budget.billsRemaining,
    savingsRemaining: budget.savingsRemaining,
    personalRemaining: budget.personalRemaining,
    forfeitedBills: budget.forfeitedBills,
    forfeitedSavings: budget.forfeitedSavings,
    forfeitedPersonal: budget.forfeitedPersonal,
    savingsGoalTarget: budget.savingsGoalTarget,
    savingsGoalCurrent: budget.savingsGoalCurrent,
    savingsGoalTargetDateMs: budget.savingsGoalTargetDateMs,
    savingsGoalTitle: budget.savingsGoalTitle,
    schemaVersion: budget.schemaVersion,
    updatedAt: Date.now(),
  };
}

export function remainingFor(
  budget: BudgetState,
  category: CategoryKey,
): number {
  switch (category) {
  case "bills":
    return budget.billsRemaining;
  case "savings":
    return budget.savingsRemaining;
  case "personal":
    return budget.personalRemaining;
  default: {
    const exhaustive: never = category;
    return exhaustive;
  }
  }
}

export function adjustRemaining(
  budget: BudgetState,
  category: CategoryKey,
  delta: number,
): void {
  switch (category) {
  case "bills":
    budget.billsRemaining += delta;
    break;
  case "savings":
    budget.savingsRemaining += delta;
    break;
  case "personal":
    budget.personalRemaining += delta;
    break;
  default: {
    const exhaustive: never = category;
    return exhaustive;
  }
  }
}

/** Distribute ONLY [amount] using the user's percentages. */
export function distributeAddedFunds(
  budget: BudgetState,
  amount: number,
): void {
  if (amount === 0) return;
  budget.billsRemaining += amount * (budget.billsPercentage / 100);
  budget.savingsRemaining += amount * (budget.savingsPercentage / 100);
  budget.personalRemaining += amount * (budget.personalPercentage / 100);
}

/** Recalculate all envelopes from Available Balance × user %. */
export function reallocateAllFromAvailableBalance(budget: BudgetState): void {
  budget.billsRemaining =
    budget.availableBalance * (budget.billsPercentage / 100);
  budget.savingsRemaining =
    budget.availableBalance * (budget.savingsPercentage / 100);
  budget.personalRemaining =
    budget.availableBalance * (budget.personalPercentage / 100);
}

/**
 * Migrate older schemas to v3 independent envelopes.
 * Mirrors Flutter BudgetProvider._migrateBudgetSchemaIfNeeded.
 */
export function migrateBudgetSchemaIfNeeded(budget: BudgetState): boolean {
  const totalRemaining =
    budget.billsRemaining +
    budget.savingsRemaining +
    budget.personalRemaining;
  const missingRemainings =
    budget.availableBalance > 0.001 && totalRemaining < 0.001;

  if (budget.schemaVersion >= CURRENT_SCHEMA_VERSION && !missingRemainings) {
    return false;
  }

  // Legacy v1 spendable reconstruction is approximate without entry history
  // on the budget doc; seed from current AB × %.
  reallocateAllFromAvailableBalance(budget);
  budget.schemaVersion = CURRENT_SCHEMA_VERSION;
  return true;
}

export function isCategory(value: unknown): value is CategoryKey {
  return value === "bills" || value === "savings" || value === "personal";
}

export function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}
