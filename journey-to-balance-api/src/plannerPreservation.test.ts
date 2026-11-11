import assert from "node:assert/strict";
import {generateKeyPairSync} from "node:crypto";
import {after, before, beforeEach, describe, it} from "node:test";

import {handleFinance, type Env} from "./finance";
import {decodeValue, encodeFields, type FirestoreValue} from "./firestore";

const PROJECT = "demo-project";
const UID = "user-1";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const USER_DOC = `${ROOT}/users/${UID}`;
const WALLET_DOC = `${USER_DOC}/wallet/data`;

type StoredDoc = {fields: Record<string, FirestoreValue>; updateTime: string};
type Write = {
  update?: {name: string; fields: Record<string, FirestoreValue>};
  updateMask?: {fieldPaths: string[]};
  delete?: string;
  currentDocument?: {exists?: boolean; updateTime?: string};
};

const ts = (iso: string): FirestoreValue => ({timestampValue: iso});
const int = (n: number): FirestoreValue => ({integerValue: String(n)});
const str = (s: string): FirestoreValue => ({stringValue: s});
const map = (fields: Record<string, FirestoreValue>): FirestoreValue => ({
  mapValue: {fields},
});

/** The planner exactly as the Flutter client stores it (real timestamps). */
const PLANNER = map({
  id: str("plan-1"),
  period: str("day"),
  startAt: ts("2026-10-27T16:00:00Z"),
  endAt: ts("2026-10-30T16:00:00Z"),
  endDate: ts("2026-10-29T16:00:00Z"),
  createdAt: ts("2026-10-27T03:15:42.123456Z"),
  billsEnabled: {booleanValue: true},
  billsAmount: int(900),
  savingsEnabled: {booleanValue: false},
  savingsAmount: int(0),
  personalEnabled: {booleanValue: false},
  personalAmount: int(0),
  total: int(900),
  alertEligible: {booleanValue: true},
  thirteenthMonth: map({
    year: int(2026),
    monthlyBasicSalaries: {
      arrayValue: {values: Array.from({length: 12}, () => int(24500))},
    },
    otherBenefits: int(0),
    updatedAt: ts("2026-10-20T08:00:00Z"),
  }),
});

const WALLET_EXTRA = {
  currency: str("PHP"),
  loans: {
    arrayValue: {
      values: [map({id: str("loan-1"), name: str("Car"), amount: int(5000)})],
    },
  },
};

let store = new Map<string, StoredDoc>();
let commits: Write[][] = [];
let version = 0;
const originalFetch = globalThis.fetch;

function nextTime(): string {
  version += 1;
  return new Date(Date.UTC(2026, 10, 1, 0, 0, version)).toISOString();
}

function seed(): void {
  store = new Map();
  commits = [];
  version = 0;
  store.set(USER_DOC, {
    updateTime: nextTime(),
    fields: {
      budget: map({
        availableBalance: int(1000),
        monthlySalary: int(1000),
        billsPercentage: int(50),
        savingsPercentage: int(20),
        personalPercentage: int(30),
        billsRemaining: int(500),
        savingsRemaining: int(200),
        personalRemaining: int(300),
        savingsGoalTarget: int(10000),
        savingsGoalCurrent: int(0),
        savingsGoalTitle: str("Goal"),
        schemaVersion: int(3),
      }),
      planner: PLANNER,
    },
  });
  store.set(WALLET_DOC, {
    updateTime: nextTime(),
    fields: {
      cashAmount: int(500),
      cards: {
        arrayValue: {
          values: [
            map({
              id: str("card-1"),
              iconAsset: str("assets/images/bank/bdo.png"),
              amount: int(300),
            }),
          ],
        },
      },
      updatedAt: ts("2026-10-25T10:00:00Z"),
      ...WALLET_EXTRA,
    },
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {"Content-Type": "application/json"},
  });
}

function applyCommit(writes: Write[]): Response {
  for (const write of writes) {
    const name = write.update?.name ?? write.delete!;
    const existing = store.get(name);
    const pre = write.currentDocument;
    if (pre?.exists === false && existing) return json({}, 409);
    if (pre?.exists === true && !existing) return json({}, 409);
    if (pre?.updateTime && existing?.updateTime !== pre.updateTime) {
      return json({}, 409);
    }
  }
  for (const write of writes) {
    if (write.delete) {
      store.delete(write.delete);
      continue;
    }
    const {name, fields} = write.update!;
    const existing = store.get(name);
    let next: Record<string, FirestoreValue>;
    if (write.updateMask) {
      next = {...(existing?.fields ?? {})};
      for (const path of write.updateMask.fieldPaths) {
        if (path in fields) next[path] = fields[path];
        else delete next[path];
      }
    } else {
      next = fields;
    }
    store.set(name, {fields: next, updateTime: nextTime()});
  }
  return json({writeResults: writes.map(() => ({}))});
}

async function fakeFetch(
  input: string | URL | Request,
  init?: RequestInit,
): Promise<Response> {
  const url = typeof input === "string" ? input : input.toString();
  if (url === "https://oauth2.googleapis.com/token") {
    return json({access_token: "test-token", expires_in: 3600});
  }
  if (url.endsWith("/documents:commit")) {
    const body = JSON.parse(String(init?.body)) as {writes: Write[]};
    commits.push(body.writes);
    return applyCommit(body.writes);
  }
  const prefix = "https://firestore.googleapis.com/v1/";
  if (url.startsWith(prefix) && (init?.method ?? "GET") === "GET") {
    const doc = store.get(url.slice(prefix.length));
    if (!doc) return json({}, 404);
    return json({fields: doc.fields, updateTime: doc.updateTime});
  }
  throw new Error(`Unexpected fetch: ${init?.method ?? "GET"} ${url}`);
}

const gate = {
  getIdempotency: async () => null,
  saveIdempotency: async () => undefined,
  enforceRateLimitsOutcome: async () => ({ok: true}),
  consumeProtectedDaily: async () => ({ok: true}),
};

let env: Env;
let request = 0;
const body = (data: Record<string, unknown>) => ({
  ...data,
  requestId: `request-${++request}-padding`,
});

before(() => {
  const {privateKey} = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: {type: "pkcs8", format: "pem"},
    publicKeyEncoding: {type: "spki", format: "pem"},
  });
  env = {
    USER_GATE: {
      idFromName: (name: string) => name,
      get: () => gate,
    },
    FIREBASE_PROJECT_ID: PROJECT,
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      client_email: "worker@demo-project.iam.gserviceaccount.com",
      private_key: privateKey,
    }),
  } as unknown as Env;
  globalThis.fetch = fakeFetch as typeof fetch;
});

after(() => {
  globalThis.fetch = originalFetch;
});

beforeEach(seed);

function assertPlannerUntouched(): void {
  const user = store.get(USER_DOC)!;
  assert.deepEqual(user.fields.planner, PLANNER);
  for (const writes of commits) {
    for (const write of writes) {
      if (write.update?.name !== USER_DOC) continue;
      assert.deepEqual(write.updateMask?.fieldPaths, ["budget"]);
      assert.deepEqual(Object.keys(write.update.fields), ["budget"]);
    }
  }
}

function assertWalletExtrasUntouched(): void {
  const wallet = store.get(WALLET_DOC)!;
  assert.deepEqual(wallet.fields.currency, WALLET_EXTRA.currency);
  assert.deepEqual(wallet.fields.loans, WALLET_EXTRA.loans);
  assert.ok("timestampValue" in wallet.fields.updatedAt);
}

const savingsBody = {
  source: "personal",
  fundingSourceId: "wallet",
  fundingSourceLabel: "Wallet",
  amount: 100,
  entryId: "goal-1",
  createdAtMs: Date.UTC(2026, 10, 2),
  savingsSources: [{locationType: "wallet", cardName: "Wallet", amount: 100}],
  savingsDestinations: [
    {locationType: "card", cardId: "card-1", cardName: "BDO", amount: 100},
  ],
};

describe("Worker finance writes keep the planner intact", () => {
  it("add transaction writes only budget", async () => {
    await handleFinance(env, UID, "add-transaction", body({
      category: "personal",
      title: "Lunch",
      amount: 50,
      entryId: "entry-1",
      createdAtMs: Date.UTC(2026, 10, 2, 4),
    }));
    assertPlannerUntouched();
    const budget = store.get(USER_DOC)!.fields.budget;
    assert.ok("mapValue" in budget);
  });

  it("refund writes only budget and keeps the entry timestamp", async () => {
    const createdAtMs = Date.UTC(2026, 10, 2, 4, 30);
    await handleFinance(env, UID, "add-transaction", body({
      category: "personal",
      title: "Lunch",
      amount: 50,
      entryId: "entry-1",
      createdAtMs,
    }));
    await handleFinance(env, UID, "delete-transaction", body({
      category: "personal",
      entryId: "entry-1",
      refund: true,
    }));
    assertPlannerUntouched();
    const entry = store.get(`${USER_DOC}/personal/entry-1`)!;
    assert.deepEqual(entry.fields.isRefund, {booleanValue: true});
    assert.deepEqual(
      entry.fields.createdAt,
      ts(new Date(createdAtMs).toISOString()),
    );
  });

  it("receive salary writes only budget", async () => {
    await handleFinance(env, UID, "receive-salary", body({}));
    assertPlannerUntouched();
  });

  it("savings contribution and undo keep planner and wallet extras", async () => {
    await handleFinance(env, UID, "contribute-to-savings-goal", body(savingsBody));
    assertPlannerUntouched();
    assertWalletExtrasUntouched();
    const wallet = store.get(WALLET_DOC)!.fields;
    assert.deepEqual(wallet.cashAmount, int(400));

    await handleFinance(env, UID, "delete-transaction", body({
      category: "personal",
      entryId: "goal-1",
      refund: true,
    }));
    assertPlannerUntouched();
    assertWalletExtrasUntouched();
    assert.deepEqual(store.get(WALLET_DOC)!.fields.cashAmount, int(500));
    assert.equal(store.has(`${USER_DOC}/personal/goal-1`), false);
  });

  it("a savings contribution still fails safely on a version conflict", async () => {
    const realFetch = globalThis.fetch;
    globalThis.fetch = (async (input, init) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("/documents:commit")) {
        // Another device changes the user document before the commit.
        const user = store.get(USER_DOC)!;
        store.set(USER_DOC, {...user, updateTime: nextTime()});
      }
      return fakeFetch(input, init);
    }) as typeof fetch;
    try {
      await assert.rejects(
        handleFinance(env, UID, "contribute-to-savings-goal", body(savingsBody)),
      );
    } finally {
      globalThis.fetch = realFetch;
    }
    assert.deepEqual(store.get(WALLET_DOC)!.fields.cashAmount, int(500));
    assertPlannerUntouched();
  });
});

describe("Firestore value codec", () => {
  it("decodes timestamps to Date and encodes them back as timestamps", () => {
    const decoded = decodeValue(PLANNER) as Record<string, unknown>;
    assert.ok(decoded.startAt instanceof Date);
    const roundTrip = encodeFields(decoded);
    assert.ok("timestampValue" in roundTrip.startAt);
    assert.ok("timestampValue" in roundTrip.endAt);
    assert.ok("timestampValue" in roundTrip.createdAt);
    const thirteenth = roundTrip.thirteenthMonth as {
      mapValue: {fields: Record<string, FirestoreValue>};
    };
    assert.ok("timestampValue" in thirteenth.mapValue.fields.updatedAt);
  });
});
