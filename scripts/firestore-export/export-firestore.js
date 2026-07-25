import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { mkdirSync, writeFileSync } from 'node:fs';

export function serializeValue(value) {
  if (value === null || value === undefined) return value ?? null;
  if (typeof value?.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }
  if (typeof value === 'object') {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      out[key] = serializeValue(val);
    }
    return out;
  }
  return value;
}

const TOP_LEVEL_COLLECTIONS = [
  'users',
  'coaches',
  'coach_groups',
  'coach_requests',
  'goals',
  'notes',
  'userpoints',
];

const COLLECTION_GROUPS = ['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'];

async function dumpTopLevelCollection(db, name, outDir) {
  const snapshot = await db.collection(name).get();
  const records = snapshot.docs.map((doc) => ({
    id: doc.id,
    data: serializeValue(doc.data()),
  }));
  writeFileSync(`${outDir}/${name}.json`, JSON.stringify(records, null, 2));
  console.log(`  ${name}: ${records.length} document(s)`);
  return records.length;
}

async function dumpCollectionGroup(db, name, outDir) {
  const snapshot = await db.collectionGroup(name).get();
  const records = snapshot.docs.map((doc) => ({
    id: doc.id,
    path: doc.ref.path,
    data: serializeValue(doc.data()),
  }));
  writeFileSync(`${outDir}/_group_${name}.json`, JSON.stringify(records, null, 2));
  console.log(`  [group] ${name}: ${records.length} document(s)`);
  return records.length;
}

async function main() {
  const serviceAccountPath = process.argv[2];
  const outDir = process.argv[3] ?? 'snapshot';
  if (!serviceAccountPath) {
    console.error('Usage: node export-firestore.js <service-account.json> [outDir]');
    process.exit(2);
  }

  mkdirSync(outDir, { recursive: true });

  const app = initializeApp({
    credential: cert(serviceAccountPath),
  });
  const db = getFirestore(app);

  console.log('Dumping top-level collections...');
  for (const name of TOP_LEVEL_COLLECTIONS) {
    await dumpTopLevelCollection(db, name, outDir);
  }

  console.log('Dumping collection groups (subcollections)...');
  for (const name of COLLECTION_GROUPS) {
    await dumpCollectionGroup(db, name, outDir);
  }

  console.log('Done.');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
