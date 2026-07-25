// backend/scripts/firebase-auth-verify/verify.js
//
// CLI wrapper around the `firebase-scrypt` npm package for verifying a
// plaintext password against a password hash exported from Firebase Auth.
//
// Usage:
//   node verify.js <hash-config.json>
// Reads JSON on stdin: { "password": string, "hash": string (base64), "salt": string (base64) }
// hash-config.json (Task 2 output) shape: { signerKey, saltSeparator, rounds, memCost }
//
// Exit codes:
//   0  -> password matches hash; stdout is "MATCH"
//   1  -> password does not match hash; stdout is "NOMATCH"
//   2  -> any other error (bad input, missing/invalid config, etc.); message on stderr
//
// NOTE: the password is deliberately read from stdin, not argv — CLI
// arguments are visible to other local users via `ps aux`, stdin is not.

const { FirebaseScrypt } = require('firebase-scrypt');
const { readFileSync } = require('node:fs');

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

async function main() {
  const hashConfigPath = process.argv[2];
  if (!hashConfigPath) {
    console.error('Usage: verify.js <hash-config.json> (reads {password,hash,salt} JSON on stdin)');
    process.exit(2);
  }

  const hashConfig = JSON.parse(readFileSync(hashConfigPath, 'utf8'));
  const input = JSON.parse(await readStdin());

  if (!input.password || !input.hash || !input.salt) {
    console.error('stdin JSON must include password, hash, and salt');
    process.exit(2);
  }

  // Constructor param names confirmed against the real installed package
  // (node_modules/firebase-scrypt/README.md + dist/firebaseScrypt.d.ts):
  // { memCost, rounds, saltSeparator, signerKey }, all required.
  const scrypt = new FirebaseScrypt({
    signerKey: hashConfig.signerKey,
    saltSeparator: hashConfig.saltSeparator,
    rounds: hashConfig.rounds,
    memCost: hashConfig.memCost,
  });

  // verify() takes positional (password, salt, hash) args and returns
  // Promise<boolean> — confirmed against the real package; the brief's
  // sketch of an object-shaped `{password, salt, passwordHash}` call does
  // not match the installed API and would throw "salt parameter missing".
  const isMatch = await scrypt.verify(input.password, input.salt, input.hash);

  if (isMatch) {
    process.stdout.write('MATCH');
    process.exit(0);
  }
  process.stdout.write('NOMATCH');
  process.exit(1);
}

main().catch((err) => {
  console.error(err?.message ?? String(err));
  process.exit(2);
});
