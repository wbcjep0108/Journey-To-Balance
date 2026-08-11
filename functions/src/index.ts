/**
 * Journey To Balance — protected financial Cloud Functions.
 *
 * Pipeline: Auth → (App Check ready) → Rate Limit → Validation →
 * Atomic Firestore transaction → Realtime client sync.
 *
 * App Check: enforceAppCheck is currently false so local/dev builds keep
 * working. Flip to true after Android/iOS App Check providers are configured.
 */

import {initializeApp} from "firebase-admin/app";
import {setGlobalOptions} from "firebase-functions/v2";
import {CallableRequest, onCall} from "firebase-functions/v2/https";

import {
  addMoneyOp,
  addTransactionOp,
  contributeToSavingsGoalOp,
  deleteTransactionOp,
  mapUnknownError,
  migrateBudgetSchemaOp,
  receiveSalaryOp,
  updateAvailableBalanceOp,
  updateMonthlySalaryOp,
  updatePercentagesOp,
  updateSavingsGoalSettingsOp,
  updateTransactionOp,
} from "./financeOps.js";
import {requireUid} from "./security.js";

initializeApp();

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

/**
 * App Check is prepared but not enforced yet.
 * Set enforceAppCheck: true after registering App Check in the Flutter apps.
 */
const callableOptions = {
  enforceAppCheck: false,
  consumeAppCheckToken: false,
};

function dataOf(request: CallableRequest): Record<string, unknown> {
  const data = request.data;
  if (data && typeof data === "object" && !Array.isArray(data)) {
    return data as Record<string, unknown>;
  }
  return {};
}

export const receiveSalary = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    const data = dataOf(request);
    return await receiveSalaryOp(
      uid,
      data.requestId as string | undefined,
    );
  } catch (error) {
    mapUnknownError(error);
  }
});

export const addMoney = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    const data = dataOf(request);
    return await addMoneyOp(
      uid,
      data.amount,
      data.requestId as string | undefined,
    );
  } catch (error) {
    mapUnknownError(error);
  }
});

export const updateAvailableBalance = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      const data = dataOf(request);
      return await updateAvailableBalanceOp(
        uid,
        data.availableBalance,
        data.requestId as string | undefined,
      );
    } catch (error) {
      mapUnknownError(error);
    }
  },
);

export const updatePercentages = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    const data = dataOf(request);
    return await updatePercentagesOp(
      uid,
      data.billsPercentage,
      data.savingsPercentage,
      data.personalPercentage,
      data.requestId as string | undefined,
    );
  } catch (error) {
    mapUnknownError(error);
  }
});

export const updateMonthlySalary = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    const data = dataOf(request);
    return await updateMonthlySalaryOp(
      uid,
      data.monthlySalary,
      data.requestId as string | undefined,
    );
  } catch (error) {
    mapUnknownError(error);
  }
});

export const addTransaction = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    return await addTransactionOp(uid, dataOf(request));
  } catch (error) {
    mapUnknownError(error);
  }
});

export const updateTransaction = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    return await updateTransactionOp(uid, dataOf(request));
  } catch (error) {
    mapUnknownError(error);
  }
});

export const deleteTransaction = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    return await deleteTransactionOp(uid, dataOf(request));
  } catch (error) {
    mapUnknownError(error);
  }
});

export const contributeToSavingsGoal = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      return await contributeToSavingsGoalOp(uid, dataOf(request));
    } catch (error) {
      mapUnknownError(error);
    }
  },
);

export const updateSavingsGoalSettings = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      return await updateSavingsGoalSettingsOp(uid, dataOf(request));
    } catch (error) {
      mapUnknownError(error);
    }
  },
);

export const migrateBudgetSchema = onCall(callableOptions, async (request) => {
  try {
    const uid = requireUid(request);
    const data = dataOf(request);
    return await migrateBudgetSchemaOp(
      uid,
      data.requestId as string | undefined,
    );
  } catch (error) {
    mapUnknownError(error);
  }
});
