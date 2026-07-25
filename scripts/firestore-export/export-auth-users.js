// scripts/firestore-export/export-auth-users.js
//
// Exports Firebase Auth users directly via the Admin SDK's listUsers(),
// rather than shelling out to `firebase auth:export`. Built as a
// replacement after the Firebase CLI proved unusable in the actual
// production environment (v15+ requires Node >=20; the server runs
// Node 18, and installing an older CLI version alongside firebase-admin
// hit an unrelated ESM/CJS dependency conflict in its transitive deps).
//
// listUsers() UserRecord objects are reshaped here into the exact JSON
// structure `firebase auth:export --format=JSON` produces (verified
// against real CLI output during development), so SnapshotReader and
// UserImporter need no changes: {"users": [{localId, email,
// emailVerified, passwordHash, salt, displayName, photoUrl,
// providerUserInfo: [{providerId, rawId, ...}]}]}.

import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { writeFileSync } from 'node:fs';

export function toExportShape(userRecord) {
  const out = {
    localId: userRecord.uid,
    email: userRecord.email,
    emailVerified: userRecord.emailVerified,
    displayName: userRecord.displayName,
    photoUrl: userRecord.photoURL,
    providerUserInfo: (userRecord.providerData || []).map((p) => ({
      providerId: p.providerId,
      rawId: p.uid,
      email: p.email,
      displayName: p.displayName,
      photoUrl: p.photoURL,
    })),
  };
  if (userRecord.passwordHash) {
    out.passwordHash = userRecord.passwordHash;
  }
  if (userRecord.passwordSalt) {
    out.salt = userRecord.passwordSalt;
  }
  return out;
}

async function main() {
  const serviceAccountPath = process.argv[2];
  const outFile = process.argv[3];
  if (!serviceAccountPath || !outFile) {
    console.error('Usage: node export-auth-users.js <service-account.json> <auth-users.json>');
    process.exit(2);
  }

  const app = initializeApp({ credential: cert(serviceAccountPath) });
  const auth = getAuth(app);

  const users = [];
  let pageToken;
  do {
    const result = await auth.listUsers(1000, pageToken);
    for (const userRecord of result.users) {
      users.push(toExportShape(userRecord));
    }
    pageToken = result.pageToken;
  } while (pageToken);

  writeFileSync(outFile, JSON.stringify({ users }, null, 2));
  console.log(`Exported ${users.length} account(s) to ${outFile}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
