// scripts/firestore-export/fetch-hash-config.js
//
// Fetches the project's SCRYPT password-hash parameters directly from the
// Identity Toolkit Admin API, authenticated via the same service account
// used for the Firestore/Auth export.
//
// This replaces the original approach (parse-hash-config.js), which tried
// to scrape these values out of `firebase auth:export`'s console output.
// Verified empirically against a real project: the current Firebase CLI
// (15.24.0) does not print hash config to the console at all during
// `auth:export`, so that approach could never succeed against real data.
// This API-based approach was verified working end-to-end against the
// real selfcare-1476e project.

import { GoogleAuth } from 'google-auth-library';
import { writeFileSync } from 'node:fs';

// Pure transform, unit-testable without real network/credentials: turns the
// Identity Toolkit API's config response into the {signerKey, saltSeparator,
// rounds, memCost} shape verify.js expects (note memoryCost -> memCost).
export function extractHashConfig(configResponseBody) {
  const hashConfig = configResponseBody?.signIn?.hashConfig;

  if (!hashConfig || hashConfig.algorithm !== 'SCRYPT') {
    throw new Error(
      `expected signIn.hashConfig.algorithm === "SCRYPT", got: ${JSON.stringify(hashConfig)}`
    );
  }

  return {
    signerKey: hashConfig.signerKey,
    saltSeparator: hashConfig.saltSeparator,
    rounds: hashConfig.rounds,
    memCost: hashConfig.memoryCost,
  };
}

export async function fetchHashConfig(serviceAccountPath, projectId) {
  const auth = new GoogleAuth({
    keyFile: serviceAccountPath,
    scopes: ['https://www.googleapis.com/auth/identitytoolkit'],
  });
  const client = await auth.getClient();
  const { token } = await client.getAccessToken();

  const url = `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId}/config`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });

  if (!res.ok) {
    throw new Error(`Identity Toolkit config request failed: ${res.status} ${await res.text()}`);
  }

  return extractHashConfig(await res.json());
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [serviceAccountPath, projectId, outPath] = process.argv.slice(2);
  if (!serviceAccountPath || !projectId || !outPath) {
    console.error('Usage: node fetch-hash-config.js <service-account.json> <projectId> <hash-config.json>');
    process.exit(2);
  }

  fetchHashConfig(serviceAccountPath, projectId)
    .then((config) => {
      writeFileSync(outPath, JSON.stringify(config, null, 2));
      console.log(`Wrote ${outPath}`);
    })
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}
