export const SUPPORTED_TRANSACTION_ICON_ASSETS = new Set([
  "material:electric_bolt",
  "material:restaurant",
  "material:router",
  "material:account_balance",
  "material:medication",
  "material:home",
  "material:directions_bus",
  "material:water_drop",
  "material:checkroom",
  "material:coffee",
  "material:theaters",
  "material:card_giftcard",
  "material:shopping_bag",
  "material:savings",
  "material:receipt_long",
  "material:person",
  "material:more_horiz",
  "assets/images/icons_bills/electricity.png",
  "assets/images/icons_bills/food.png",
  "assets/images/icons_bills/internet.png",
  "assets/images/icons_bills/loan.png",
  "assets/images/icons_bills/medicine.png",
  "assets/images/icons_bills/rent.png",
  "assets/images/icons_bills/transpo.png",
  "assets/images/icons_bills/water.png",
  "assets/images/icons_bills/others.png",
  "assets/images/icons_personal/clothes.png",
  "assets/images/icons_personal/coffee.png",
  "assets/images/icons_personal/entertainment.png",
  "assets/images/icons_personal/gift.png",
  "assets/images/icons_personal/restaurant.png",
  "assets/images/icons_personal/shopping.png",
  "assets/images/icons_personal/others.png",
  "assets/images/icons_savings/emergency fund.png",
]);

export function normalizeTransactionIconAsset(
  value: unknown,
): string | undefined {
  if (value == null) return undefined;
  if (typeof value !== "string") {
    throw new Error("iconAsset must be a string.");
  }
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  if (!SUPPORTED_TRANSACTION_ICON_ASSETS.has(trimmed)) {
    throw new Error(`Unsupported iconAsset: ${trimmed}`);
  }
  return trimmed;
}

export function withTransactionIcon<T extends Record<string, unknown>>(
  data: T,
  iconAsset: string | undefined,
): T & {iconAsset?: string} {
  return iconAsset ? {...data, iconAsset} : data;
}
