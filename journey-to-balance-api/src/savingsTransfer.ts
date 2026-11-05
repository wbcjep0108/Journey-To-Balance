import {badRequest, conflict, internal} from "./errors";

export const MAX_SAVINGS_TRANSFER_PARTS = 10;

export type SavingsTransferPart = {
  locationType: "wallet" | "card";
  cardId?: string;
  cardName: string;
  amount: number;
};

export type SavingsTransferPayload = {
  sources: SavingsTransferPart[];
  destinations: SavingsTransferPart[];
};

const toCents = (amount: number): number => Math.round(amount * 100);

function parseParts(value: unknown, label: string): SavingsTransferPart[] {
  if (!Array.isArray(value) || value.length < 1 ||
      value.length > MAX_SAVINGS_TRANSFER_PARTS) {
    throw badRequest(
      `${label} must contain 1 to ${MAX_SAVINGS_TRANSFER_PARTS} locations.`,
    );
  }
  const seen = new Set<string>();
  return value.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw badRequest(`Invalid ${label} location.`);
    }
    const part = raw as Record<string, unknown>;
    const locationType = part.locationType;
    const cardId = typeof part.cardId === "string" ? part.cardId.trim() : "";
    const cardName = typeof part.cardName === "string" ?
      part.cardName.trim() : "";
    const amount = part.amount;
    if (locationType !== "wallet" && locationType !== "card") {
      throw badRequest(`Invalid ${label} location type.`);
    }
    if (!cardName || cardName.length > 80 ||
        (locationType === "card" && (!cardId || cardId.length > 128)) ||
        typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0 ||
        Math.abs(amount * 100 - toCents(amount)) > 0.000001) {
      throw badRequest(`Invalid ${label} allocation.`);
    }
    const id = locationType === "wallet" ? "wallet" : cardId;
    if (seen.has(id)) throw badRequest(`Duplicate ${label} location.`);
    seen.add(id);
    return {
      locationType,
      ...(locationType === "card" ? {cardId} : {}),
      cardName,
      amount: toCents(amount) / 100,
    };
  });
}

export function parseSavingsTransferPayload(
  body: Record<string, unknown>,
  totalAmount: number,
): SavingsTransferPayload | undefined {
  const sourcesRaw = body.savingsSources;
  const destinationsRaw = body.savingsDestinations;
  if (sourcesRaw == null && destinationsRaw == null) return undefined;
  if (sourcesRaw == null || destinationsRaw == null) {
    throw badRequest("Both savingsSources and savingsDestinations are required.");
  }
  if (Math.abs(totalAmount * 100 - toCents(totalAmount)) > 0.000001) {
    throw badRequest("Contribution amount must be rounded to centavos.");
  }
  const sources = parseParts(sourcesRaw, "FROM");
  const destinations = parseParts(destinationsRaw, "TO");
  const totalCents = toCents(totalAmount);
  const sourceCents = sources.reduce((sum, part) => sum + toCents(part.amount), 0);
  const destinationCents = destinations.reduce(
    (sum, part) => sum + toCents(part.amount),
    0,
  );
  if (sourceCents !== totalCents || destinationCents !== totalCents) {
    throw badRequest("FROM and TO amounts must each equal the contribution total.");
  }
  return {sources, destinations};
}

type WalletCard = Record<string, unknown> & {
  id: string;
  amount: number;
};

function walletCards(wallet: Record<string, unknown>): WalletCard[] {
  const raw = wallet.cards;
  if (!Array.isArray(raw)) return [];
  return raw.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw internal("Wallet card data is invalid.");
    }
    const card = item as Record<string, unknown>;
    if (typeof card.id !== "string" || typeof card.amount !== "number" ||
        !Number.isFinite(card.amount)) {
      throw internal("Wallet card data is invalid.");
    }
    return {...card, id: card.id, amount: card.amount};
  });
}

function partId(part: SavingsTransferPart): string {
  return part.locationType === "wallet" ? "wallet" : part.cardId!;
}

export function applySavingsTransfer(
  wallet: Record<string, unknown>,
  transfer: SavingsTransferPayload,
): Record<string, unknown> {
  const cards = walletCards(wallet);
  const balances = new Map<string, number>([
    ["wallet", toCents(
      typeof wallet.cashAmount === "number" ? wallet.cashAmount : 0,
    )],
    ...cards.map((card) => [card.id, toCents(card.amount)] as const),
  ]);
  for (const source of transfer.sources) {
    const id = partId(source);
    const balance = balances.get(id);
    if (balance == null) throw badRequest(`Unknown FROM card: ${source.cardName}.`);
    if (toCents(source.amount) > balance) {
      throw conflict(`${source.cardName} does not have enough balance.`);
    }
  }
  const deltas = new Map<string, number>();
  for (const source of transfer.sources) {
    const id = partId(source);
    deltas.set(id, (deltas.get(id) ?? 0) - toCents(source.amount));
  }
  for (const destination of transfer.destinations) {
    const id = partId(destination);
    if (!balances.has(id)) {
      throw badRequest(`Unknown TO card: ${destination.cardName}.`);
    }
    deltas.set(id, (deltas.get(id) ?? 0) + toCents(destination.amount));
  }
  for (const [id, delta] of deltas) {
    const next = (balances.get(id) ?? 0) + delta;
    if (next < 0) throw conflict("A FROM location would become negative.");
    balances.set(id, next);
  }
  return {
    ...wallet,
    cashAmount: (balances.get("wallet") ?? 0) / 100,
    cards: cards.map((card) => ({
      ...card,
      amount: (balances.get(card.id) ?? 0) / 100,
    })),
    updatedAt: new Date(),
  };
}

export function reverseSavingsTransfer(
  wallet: Record<string, unknown>,
  transfer: SavingsTransferPayload,
): {wallet: Record<string, unknown>; fallbacks: string[]} {
  const cards = walletCards(wallet);
  const balances = new Map<string, number>([
    ["wallet", toCents(
      typeof wallet.cashAmount === "number" ? wallet.cashAmount : 0,
    )],
    ...cards.map((card) => [card.id, toCents(card.amount)] as const),
  ]);
  const fallbacks = new Set<string>();
  const resolvedId = (part: SavingsTransferPart): string => {
    const id = partId(part);
    if (balances.has(id)) return id;
    fallbacks.add(
      `${part.cardName} was removed, so its reversal used Wallet.`,
    );
    return "wallet";
  };
  const deltas = new Map<string, number>();
  // Undo credits every original source and debits every original destination.
  for (const source of transfer.sources) {
    const id = resolvedId(source);
    deltas.set(id, (deltas.get(id) ?? 0) + toCents(source.amount));
  }
  for (const destination of transfer.destinations) {
    const id = resolvedId(destination);
    deltas.set(id, (deltas.get(id) ?? 0) - toCents(destination.amount));
  }
  for (const [id, delta] of deltas) {
    const next = (balances.get(id) ?? 0) + delta;
    if (next < 0) {
      throw conflict(
        `${id === "wallet" ? "Wallet" : "A destination card"} ` +
        "does not have enough balance to undo this transfer.",
      );
    }
    balances.set(id, next);
  }
  return {
    wallet: {
      ...wallet,
      cashAmount: (balances.get("wallet") ?? 0) / 100,
      cards: cards.map((card) => ({
        ...card,
        amount: (balances.get(card.id) ?? 0) / 100,
      })),
      updatedAt: new Date(),
    },
    fallbacks: [...fallbacks],
  };
}
