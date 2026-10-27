import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

const DEFAULT_ICONS = {
  bills: "material:receipt_long",
  savings: "material:savings",
  personal: "material:person",
};
const WRITE_BATCH_SIZE = 450;

function readArgument(name) {
  const equalsPrefix = `--${name}=`;
  const equalsValue = process.argv.find((value) => value.startsWith(equalsPrefix));
  if (equalsValue) return equalsValue.slice(equalsPrefix.length);

  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

const projectId = readArgument("project") ?? process.env.GCLOUD_PROJECT;
const applyChanges = process.argv.includes("--apply");
const dryRun = !applyChanges || process.argv.includes("--dry-run");

if (!projectId) {
  console.error(
    "Provide --project <project-id> or set GCLOUD_PROJECT before running.",
  );
  process.exitCode = 1;
} else {
  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  let scanned = 0;
  let changed = 0;
  let batch = db.batch();
  let batchSize = 0;

  for (const [category, iconAsset] of Object.entries(DEFAULT_ICONS)) {
    const snapshot = await db.collectionGroup(category).get();
    for (const document of snapshot.docs) {
      scanned += 1;
      const currentIcon = document.get("iconAsset");
      if (typeof currentIcon === "string" && currentIcon.trim()) continue;

      changed += 1;
      console.log(`${dryRun ? "Would update" : "Updating"} ${document.ref.path} -> ${iconAsset}`);
      if (dryRun) continue;

      batch.update(document.ref, {iconAsset});
      batchSize += 1;
      if (batchSize >= WRITE_BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }
  }

  if (!dryRun && batchSize > 0) await batch.commit();
  console.log(
    `${dryRun ? "Dry run" : "Migration"} complete: scanned ${scanned}, ${changed} transaction(s) ${dryRun ? "would change" : "changed"}.`,
  );
}
