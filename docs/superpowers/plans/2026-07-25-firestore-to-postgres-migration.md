# Firestore → PostgreSQL Data Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate existing users (accounts + passwords) and their historical app data out of Firestore/Firebase Auth into the Laravel/Postgres backend (`backend/`) as a one-time cutover, so existing users keep working on the new Laravel-backed app without re-signing up.

**Architecture:** A Node.js script extracts a frozen snapshot of Firestore + Firebase Auth to local JSON files. A Laravel Artisan command (`firestore:import`) reads that snapshot and upserts into Postgres via a set of per-domain Importer classes, resolving foreign keys through `firestore_id`/`firebase_uid` mapping columns. Existing Firebase password hashes are preserved in holding columns and verified at login time (via a small Node helper that Laravel shells out to, since Firebase's password hash algorithm needs the same tooling family the Firebase CLI itself uses), then lazily rehashed to native Laravel bcrypt on first successful login.

**Tech Stack:** Node.js 18+ (`firebase-admin`, `firebase-scrypt`), Laravel 12 / PHP 8.2, PostgreSQL, PHPUnit (existing convention: class-based tests under `backend/tests/Feature`, `RefreshDatabase`, sqlite `:memory:` for tests).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-25-firestore-to-postgres-migration-design.md` — read it before starting; this plan implements it exactly.
- Hard cutover, one-time migration. No ongoing dual-write/sync is being built.
- The migration must be **idempotent and re-runnable**: every imported row is matched by an explicit `firestore_id` (or `firebase_uid` on `users`) mapping column, never by reusing the Firestore document ID as the Postgres primary key — Laravel already generates fresh `Str::uuid()` values for these string-PK tables (`GoalController.php`, `ExerciseController.php`, etc.), so reusing old IDs risks confusing app code; a mapping column avoids that entirely.
- `firestore:import` must support `--dry-run` (rolls back every write) and must never abort the whole run on one bad record — log it via `ImportReport` and continue.
- Do not commit anything (per this project's standing instruction) unless explicitly told to — this plan's steps still say "Commit" per the writing-plans convention, but treat those as "stage the change and stop" unless the person running the plan is told otherwise. **Do not push.**
- Never commit `snapshot/` output or any Firebase service-account key — both contain real user data (including password hashes) and must stay untracked.
- The `firebase-scrypt` npm package's exact verify-call shape must be confirmed against the installed package (Task 4) before being trusted — do not assume the API sketched in this plan is byte-perfect without checking `node_modules/firebase-scrypt` after install.
- `userpoints` field mapping (Task 14) is explicitly unconfirmed until checked against a real exported snapshot — the current `UserPointApiService` payload shape is used as a starting hypothesis only, not a verified fact.

---

## File Structure

```
scripts/firestore-export/                 # one-time extraction tooling (never deployed)
  package.json
  .gitignore                              # ignores snapshot/, *.json service account keys
  export-firestore.js                     # dumps top-level collections + collectionGroups
  export-auth.sh                          # wraps `firebase auth:export` + hash-config capture
  parse-hash-config.js                    # extracts SCRYPT params from the CLI's stdout log

backend/scripts/firebase-auth-verify/      # ships to production, used at login time
  package.json
  verify.js                               # verifies one password against a Firebase scrypt hash

backend/app/Services/
  FirebaseScryptVerifier.php              # PHP wrapper that shells out to verify.js

backend/app/Services/FirestoreImport/
  SnapshotReader.php                      # reads snapshot/*.json into plain arrays
  ImportReport.php                        # accumulates counts + skipped-record log
  DryRunAbort.php                         # marker exception used to roll back dry runs
  UserImporter.php                        # users + coaches + Firebase Auth export
  CoachRelationshipImporter.php           # coach_groups, coach_requests, coach_mentees
  GoalImporter.php                        # goals + goal_tasks/updates/comments/merits
  NotesImporter.php                       # notes -> community_posts, note comments
  WellnessImporter.php                    # users/{uid}/wellness/fasting(+history)
  UserPointsImporter.php                  # userpoints -> user_points

backend/app/Console/Commands/
  ImportFirestoreData.php                 # `php artisan firestore:import` orchestrator

backend/database/migrations/
  2026_07_25_000001_add_firestore_migration_columns_to_users_table.php
  2026_07_25_000002_add_firestore_id_columns_for_migration_import.php

backend/app/Http/Controllers/Api/AuthController.php   # modified: legacy-password login branch

backend/app/Models/
  User.php, Goal.php, GoalTask.php, GoalUpdate.php, GoalComment.php, GoalMerit.php,
  CoachGroup.php, CoachRequest.php, CommunityPost.php, NoteComment.php, FastingHistory.php
                                           # modified: add firestore_id/firebase_uid to $fillable

backend/tests/Feature/FirestoreImport/
  UserImporterTest.php
  CoachRelationshipImporterTest.php
  GoalImporterTest.php
  NotesImporterTest.php
  WellnessImporterTest.php
  UserPointsImporterTest.php
backend/tests/Feature/FirebaseScryptVerifierTest.php
backend/tests/Feature/AuthTest.php        # modified: add legacy-password login test
```

---

### Task 1: Node Firestore extraction scaffold + collection dumper

**Files:**
- Create: `scripts/firestore-export/package.json`
- Create: `scripts/firestore-export/.gitignore`
- Create: `scripts/firestore-export/export-firestore.js`
- Test: `scripts/firestore-export/export-firestore.test.js` (unit test of the pure transform function, no live Firestore needed)

**Interfaces:**
- Produces: `snapshot/<collection>.json` — JSON array of `{id: string, data: object}`, for each plain top-level collection.
- Produces: `snapshot/_group_<name>.json` — JSON array of `{id: string, path: string, data: object}`, for each `collectionGroup` (subcollection) dump. `path` is the full Firestore document path (e.g. `goals/abc123/tasks/xyz789`), which downstream Laravel importers parse to find the parent doc's ID.
- Consumed by: Task 8's `SnapshotReader` (must read exactly these two file shapes).

This project already has a live Firebase project (`selfcare-1476e`, see `firebase.json`) with these Firestore collections still holding historical data: `users`, `coaches`, `coach_groups`, `coach_requests`, `goals` (+ subcollections `tasks`, `updates`, `comments`, `merits`), `notes` (+ subcollection `comments`), `users/{uid}/wellness/fasting` (+ subcollection `history`), `userpoints`. The `test` collection is confirmed dead/dev-only and is excluded.

- [ ] **Step 1: Create the Node project**

```bash
mkdir -p scripts/firestore-export
cat > scripts/firestore-export/package.json <<'EOF'
{
  "name": "firestore-export",
  "private": true,
  "type": "module",
  "version": "1.0.0",
  "dependencies": {
    "firebase-admin": "^13.0.0"
  },
  "scripts": {
    "export": "node export-firestore.js",
    "test": "node --test"
  }
}
EOF
cat > scripts/firestore-export/.gitignore <<'EOF'
snapshot/
service-account*.json
*.log
node_modules/
EOF
cd scripts/firestore-export && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 2: Write a failing test for the plain-document serializer**

The dumper needs a pure function that converts a Firestore `DocumentSnapshot` into the `{id, data}` shape, handling Firestore's `Timestamp` objects (convert to ISO 8601 strings, since JSON has no native date type and PHP's `Carbon::parse` needs a string it can read).

```javascript
// scripts/firestore-export/export-firestore.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { serializeValue } from './export-firestore.js';

test('serializeValue converts a Firestore-Timestamp-like object to an ISO string', () => {
  const fakeTimestamp = { toDate: () => new Date('2025-01-15T10:00:00.000Z') };
  assert.equal(serializeValue(fakeTimestamp), '2025-01-15T10:00:00.000Z');
});

test('serializeValue passes through plain scalars unchanged', () => {
  assert.equal(serializeValue('hello'), 'hello');
  assert.equal(serializeValue(42), 42);
  assert.equal(serializeValue(true), true);
  assert.equal(serializeValue(null), null);
});

test('serializeValue recurses into arrays and plain objects', () => {
  const fakeTimestamp = { toDate: () => new Date('2025-01-15T10:00:00.000Z') };
  const result = serializeValue({
    items: [1, fakeTimestamp],
    nested: { createdAt: fakeTimestamp },
  });
  assert.deepEqual(result, {
    items: [1, '2025-01-15T10:00:00.000Z'],
    nested: { createdAt: '2025-01-15T10:00:00.000Z' },
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd scripts/firestore-export && npm test`
Expected: FAIL — `export-firestore.js` doesn't exist yet / `serializeValue` is not exported.

- [ ] **Step 4: Implement the extraction script**

```javascript
// scripts/firestore-export/export-firestore.js
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd scripts/firestore-export && npm test`
Expected: PASS, all 3 assertions green.

- [ ] **Step 6: Commit**

```bash
git add scripts/firestore-export/
git commit -m "feat: add Node Firestore extraction script for Postgres migration"
```

---

### Task 2: Firebase Auth export + hash-config capture

**Files:**
- Create: `scripts/firestore-export/export-auth.sh`
- Create: `scripts/firestore-export/parse-hash-config.js`
- Test: `scripts/firestore-export/parse-hash-config.test.js`

**Interfaces:**
- Produces: `snapshot/auth-users.json` — the raw output of `firebase auth:export --format=JSON`, shape `{ "users": [ { "localId", "email", "emailVerified", "passwordHash", "salt", "displayName", "photoUrl", "providerUserInfo": [{"providerId", "rawId", ...}], ... } ] }`.
- Produces: `snapshot/hash-config.json` — `{ "signerKey": string, "saltSeparator": string, "rounds": number, "memCost": number }`.
- Consumed by: Task 4's Node verifier and Task 8's `SnapshotReader::authUsers()`.

The Firebase CLI's `auth:export` command prints the project's SCRYPT hash parameters (signer key, salt separator, rounds, memory cost) to the console after exporting — it does not put them in the JSON file itself. `parse-hash-config.js` extracts those 4 values from that console output.

- [ ] **Step 1: Write a failing test for the hash-config parser**

```javascript
// scripts/firestore-export/parse-hash-config.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHashConfig } from './parse-hash-config.js';

test('parseHashConfig extracts all four SCRYPT parameters from CLI log output', () => {
  const log = `
Exporting accounts to snapshot/auth-users.json
Exported 42 account(s) successfully.
IMPORTANT: The following hash parameters are required to migrate these accounts:
base64_signer_key: ABCDefgh1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP==
base64_salt_separator: Bw==
rounds: 8
mem_cost: 14
`;
  assert.deepEqual(parseHashConfig(log), {
    signerKey: 'ABCDefgh1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP==',
    saltSeparator: 'Bw==',
    rounds: 8,
    memCost: 14,
  });
});

test('parseHashConfig throws a clear error when a parameter is missing', () => {
  assert.throws(() => parseHashConfig('no hash config here'), /could not find/i);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts/firestore-export && node --test parse-hash-config.test.js`
Expected: FAIL — module doesn't exist.

- [ ] **Step 3: Implement the parser + the export wrapper script**

```javascript
// scripts/firestore-export/parse-hash-config.js
export function parseHashConfig(log) {
  const patterns = {
    signerKey: /base64_signer_key:\s*(\S+)/i,
    saltSeparator: /base64_salt_separator:\s*(\S+)/i,
    rounds: /rounds:\s*(\d+)/i,
    memCost: /mem_cost:\s*(\d+)/i,
  };

  const result = {};
  for (const [key, pattern] of Object.entries(patterns)) {
    const match = log.match(pattern);
    if (!match) {
      throw new Error(`could not find "${key}" in the Firebase auth:export log output`);
    }
    result[key] = key === 'rounds' || key === 'memCost' ? Number(match[1]) : match[1];
  }
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { readFileSync, writeFileSync } = await import('node:fs');
  const [logPath, outPath] = process.argv.slice(2);
  if (!logPath || !outPath) {
    console.error('Usage: node parse-hash-config.js <auth-export.log> <hash-config.json>');
    process.exit(2);
  }
  const config = parseHashConfig(readFileSync(logPath, 'utf8'));
  writeFileSync(outPath, JSON.stringify(config, null, 2));
  console.log(`Wrote ${outPath}`);
}
```

```bash
# scripts/firestore-export/export-auth.sh
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-selfcare-1476e}"
OUT_DIR="${2:-snapshot}"

mkdir -p "$OUT_DIR"

firebase auth:export "$OUT_DIR/auth-users.json" \
  --format=JSON \
  --project "$PROJECT_ID" \
  | tee "$OUT_DIR/auth-export.log"

node parse-hash-config.js "$OUT_DIR/auth-export.log" "$OUT_DIR/hash-config.json"

echo "Auth export complete: $OUT_DIR/auth-users.json, $OUT_DIR/hash-config.json"
```

```bash
chmod +x scripts/firestore-export/export-auth.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts/firestore-export && node --test parse-hash-config.test.js`
Expected: PASS.

- [ ] **Step 5: Manual verification (requires real Firebase CLI access — not automatable here)**

Run: `firebase login` (if not already), then `bash scripts/firestore-export/export-auth.sh selfcare-1476e scripts/firestore-export/snapshot`
Expected: `snapshot/auth-users.json` and `snapshot/hash-config.json` are created; `hash-config.json` has non-empty `signerKey`/`saltSeparator`/`rounds`/`memCost`. If the console output format differs from what `parseHashConfig` expects, adjust the regex patterns in Step 3 to match the real output before continuing — this step is the ground truth, not the hand-written test above.

- [ ] **Step 6: Commit**

```bash
git add scripts/firestore-export/export-auth.sh scripts/firestore-export/parse-hash-config.js scripts/firestore-export/parse-hash-config.test.js
git commit -m "feat: add Firebase Auth export wrapper with hash-config extraction"
```

---

### Task 3: Laravel migrations for mapping/legacy columns

**Files:**
- Create: `backend/database/migrations/2026_07_25_000001_add_firestore_migration_columns_to_users_table.php`
- Create: `backend/database/migrations/2026_07_25_000002_add_firestore_id_columns_for_migration_import.php`
- Test: `backend/tests/Feature/FirestoreMigrationColumnsTest.php`

**Interfaces:**
- Produces: `users.firebase_uid` (string, nullable, unique), `users.legacy_password_hash` (text, nullable), `users.legacy_password_salt` (string, nullable), `users.bio` (text, nullable); `users.password` becomes nullable.
- Produces: `firestore_id` (string, nullable, unique) on `goals`, `goal_tasks`, `goal_updates`, `goal_comments`, `goal_merits`, `coach_groups`, `coach_requests`, `community_posts`, `note_comments`, `fasting_history`.
- Consumed by: every Importer class in Tasks 9–14, and `AuthController::login()` in Task 6.

- [ ] **Step 1: Write a failing test asserting the new columns exist**

```php
<?php
// backend/tests/Feature/FirestoreMigrationColumnsTest.php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class FirestoreMigrationColumnsTest extends TestCase
{
    use RefreshDatabase;

    public function test_users_table_has_migration_columns(): void
    {
        $this->assertTrue(Schema::hasColumns('users', [
            'firebase_uid',
            'legacy_password_hash',
            'legacy_password_salt',
            'bio',
        ]));
    }

    public function test_password_column_is_nullable(): void
    {
        $column = collect(Schema::getColumns('users'))->firstWhere('name', 'password');
        $this->assertNotNull($column);
        $this->assertTrue($column['nullable']);
    }

    public function test_firestore_id_columns_exist_on_migrated_tables(): void
    {
        $tables = [
            'goals', 'goal_tasks', 'goal_updates', 'goal_comments', 'goal_merits',
            'coach_groups', 'coach_requests', 'community_posts', 'note_comments',
            'fasting_history',
        ];

        foreach ($tables as $table) {
            $this->assertTrue(
                Schema::hasColumn($table, 'firestore_id'),
                "expected {$table} to have a firestore_id column"
            );
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=FirestoreMigrationColumnsTest`
Expected: FAIL — columns don't exist yet.

- [ ] **Step 3: Write the migrations**

```php
<?php
// backend/database/migrations/2026_07_25_000001_add_firestore_migration_columns_to_users_table.php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('firebase_uid')->nullable()->unique()->after('id');
            $table->text('legacy_password_hash')->nullable()->after('password');
            $table->string('legacy_password_salt')->nullable()->after('legacy_password_hash');
            $table->text('bio')->nullable()->after('profile_pic');
            $table->string('password')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropUnique(['firebase_uid']);
            $table->dropColumn(['firebase_uid', 'legacy_password_hash', 'legacy_password_salt', 'bio']);
            $table->string('password')->nullable(false)->change();
        });
    }
};
```

```php
<?php
// backend/database/migrations/2026_07_25_000002_add_firestore_id_columns_for_migration_import.php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private array $tables = [
        'goals', 'goal_tasks', 'goal_updates', 'goal_comments', 'goal_merits',
        'coach_groups', 'coach_requests', 'community_posts', 'note_comments',
        'fasting_history',
    ];

    public function up(): void
    {
        foreach ($this->tables as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->string('firestore_id')->nullable()->unique()->after('id');
            });
        }
    }

    public function down(): void
    {
        foreach ($this->tables as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->dropUnique([$blueprint->getTable().'_firestore_id_unique']);
                $blueprint->dropColumn('firestore_id');
            });
        }
    }
};
```

- [ ] **Step 4: Run migrations and the test**

Run: `cd backend && php artisan migrate && php artisan test --filter=FirestoreMigrationColumnsTest`
Expected: PASS, all 3 assertions green.

- [ ] **Step 5: Add the new columns to each model's `$fillable`**

Edit `backend/app/Models/User.php` — add to `$fillable`: `'firebase_uid', 'legacy_password_hash', 'legacy_password_salt', 'bio'`, and add `'legacy_password_hash', 'legacy_password_salt'` to `$hidden` alongside `'password'`.

Edit each of `Goal.php`, `GoalTask.php`, `GoalUpdate.php`, `GoalComment.php`, `GoalMerit.php`, `CoachGroup.php`, `CoachRequest.php`, `CommunityPost.php`, `NoteComment.php`, `FastingHistory.php` — add `'firestore_id'` to `$fillable`.

- [ ] **Step 6: Commit**

```bash
git add backend/database/migrations/2026_07_25_000001_add_firestore_migration_columns_to_users_table.php \
        backend/database/migrations/2026_07_25_000002_add_firestore_id_columns_for_migration_import.php \
        backend/tests/Feature/FirestoreMigrationColumnsTest.php \
        backend/app/Models/User.php backend/app/Models/Goal.php backend/app/Models/GoalTask.php \
        backend/app/Models/GoalUpdate.php backend/app/Models/GoalComment.php backend/app/Models/GoalMerit.php \
        backend/app/Models/CoachGroup.php backend/app/Models/CoachRequest.php \
        backend/app/Models/CommunityPost.php backend/app/Models/NoteComment.php backend/app/Models/FastingHistory.php
git commit -m "feat: add firestore_id/firebase_uid mapping columns for data migration"
```

---

### Task 4: Node Firebase-scrypt password verifier script

**Files:**
- Create: `backend/scripts/firebase-auth-verify/package.json`
- Create: `backend/scripts/firebase-auth-verify/verify.js`
- Test: manual (see Step 5 — this needs a real exported hash/salt/password to validate against, which only exists after Task 2's export runs against production)

**Interfaces:**
- Consumes: JSON on stdin, `{ "password": string, "hash": string (base64), "salt": string (base64) }`, plus a `hashConfigPath` CLI argument pointing at `snapshot/hash-config.json` (Task 2's output, shape `{signerKey, saltSeparator, rounds, memCost}`).
- Produces: exit code `0` and stdout `MATCH` when the password verifies; exit code `1` and stdout `NOMATCH` when it doesn't; exit code `2` and a message on stderr for any other error (bad input, missing config).
- Consumed by: Task 5's `FirebaseScryptVerifier.php`.

Firebase Auth's own password hashing is a proprietary "modified scrypt" — Google publishes the 4 hash parameters (via the export in Task 2) specifically so other systems can reimplement verification outside Firebase. `firebase-scrypt` is an existing npm package built for exactly this migration scenario, so this task uses it rather than hand-rolling the algorithm. Its exact call signature must be confirmed against what actually installs — Step 2 does that confirmation before Step 3 relies on it.

- [ ] **Step 1: Create the Node project and install the dependency**

```bash
mkdir -p backend/scripts/firebase-auth-verify
cat > backend/scripts/firebase-auth-verify/package.json <<'EOF'
{
  "name": "firebase-auth-verify",
  "private": true,
  "type": "commonjs",
  "version": "1.0.0",
  "dependencies": {
    "firebase-scrypt": "^1.1.1"
  }
}
EOF
cd backend/scripts/firebase-auth-verify && npm install
```

Expected: install succeeds. If `firebase-scrypt@^1.1.1` doesn't resolve, run `npm view firebase-scrypt versions` and pin to whatever the latest published version actually is.

- [ ] **Step 2: Confirm the installed package's real API**

Run: `cat backend/scripts/firebase-auth-verify/node_modules/firebase-scrypt/README.md` (or open `node_modules/firebase-scrypt/index.js` / `lib/` if there's no README).

Confirm: the constructor's expected parameter names for signer key / salt separator / rounds / mem cost, and the verify method's name and argument shape (a `.verify({password, salt, passwordHash})` returning a `Promise<boolean>` is the expected shape below — adjust Step 3's code to match whatever the real package actually exposes before moving on).

- [ ] **Step 3: Implement the verifier CLI**

```javascript
// backend/scripts/firebase-auth-verify/verify.js
const FirebaseScrypt = require('firebase-scrypt');
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

  const scrypt = new FirebaseScrypt({
    signerKey: hashConfig.signerKey,
    saltSeparator: hashConfig.saltSeparator,
    rounds: hashConfig.rounds,
    memCost: hashConfig.memCost,
  });

  const isMatch = await scrypt.verify({
    password: input.password,
    salt: input.salt,
    passwordHash: input.hash,
  });

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
```

- [ ] **Step 4: Adjust to match the real package API if Step 2 found differences**

If the constructor or verify-call shape from Step 2 differs from Step 3's code, update Step 3's code now to match reality (parameter names in particular — some versions use `memCost`, others `mem_cost`, in their public API even though the same 4 concepts always exist).

- [ ] **Step 5: Manual verification against a real account (required before trusting this — the actual correctness gate)**

Pick one real user's exported record from `snapshot/auth-users.json` (Task 2's output) whose password you personally know (e.g. your own dev/test account), and run:

```bash
cd backend/scripts/firebase-auth-verify
echo '{"password":"<the real password>","hash":"<passwordHash from auth-users.json>","salt":"<salt from auth-users.json>"}' \
  | node verify.js ../../../scripts/firestore-export/snapshot/hash-config.json
echo "exit code: $?"
```

Expected: prints `MATCH`, exit code `0`. Also verify the negative case with a deliberately wrong password prints `NOMATCH` with exit code `1`. **Do not proceed to Task 5 until this passes against a real account** — this is the one part of the whole migration where a subtle bug fails silently (wrong output, not a crash), so it needs to be proven against real data, not just code-reviewed.

- [ ] **Step 6: Commit**

```bash
git add backend/scripts/firebase-auth-verify/package.json backend/scripts/firebase-auth-verify/verify.js
git commit -m "feat: add Firebase scrypt password verifier for migrated accounts"
```

---

### Task 5: PHP `FirebaseScryptVerifier` service

**Files:**
- Create: `backend/app/Services/FirebaseScryptVerifier.php`
- Test: `backend/tests/Feature/FirebaseScryptVerifierTest.php`

**Interfaces:**
- Produces: `FirebaseScryptVerifier::verify(string $plainPassword, string $base64Hash, string $base64Salt): bool`.
- Consumes: `config('services.firebase_scrypt.node_verifier_path')` and `config('services.firebase_scrypt.hash_config_path')` (new config keys added in Step 3).
- Consumed by: `AuthController::login()` in Task 6.

The plaintext password is passed to the Node subprocess via **stdin**, not as a CLI argument — CLI arguments are visible to any other process on the machine via `ps aux`, which is not an acceptable way to handle a password even briefly.

- [ ] **Step 1: Write a failing test**

This test fakes the Node verifier with a tiny throwaway script so it doesn't depend on real Firebase data — it only proves `FirebaseScryptVerifier` invokes a subprocess correctly and interprets exit codes correctly, not that the real crypto is right (Task 4 Step 5 already proved that separately).

```php
<?php
// backend/tests/Feature/FirebaseScryptVerifierTest.php

namespace Tests\Feature;

use App\Services\FirebaseScryptVerifier;
use Tests\TestCase;

class FirebaseScryptVerifierTest extends TestCase
{
    private string $fakeVerifierPath;
    private string $fakeConfigPath;

    protected function setUp(): void
    {
        parent::setUp();

        // A stand-in for verify.js that matches on a fixed password without touching real crypto.
        $this->fakeVerifierPath = sys_get_temp_dir().'/fake-verify-'.uniqid().'.js';
        file_put_contents($this->fakeVerifierPath, <<<'JS'
            let data = '';
            process.stdin.on('data', (c) => { data += c; });
            process.stdin.on('end', () => {
                const input = JSON.parse(data);
                if (input.password === 'correct-password' && input.hash === 'known-hash' && input.salt === 'known-salt') {
                    process.stdout.write('MATCH');
                    process.exit(0);
                }
                process.stdout.write('NOMATCH');
                process.exit(1);
            });
            JS);

        $this->fakeConfigPath = sys_get_temp_dir().'/fake-hash-config-'.uniqid().'.json';
        file_put_contents($this->fakeConfigPath, json_encode(['signerKey' => 'x', 'saltSeparator' => 'y', 'rounds' => 8, 'memCost' => 14]));
    }

    protected function tearDown(): void
    {
        @unlink($this->fakeVerifierPath);
        @unlink($this->fakeConfigPath);
        parent::tearDown();
    }

    public function test_verify_returns_true_when_the_node_script_reports_a_match(): void
    {
        $verifier = new FirebaseScryptVerifier($this->fakeVerifierPath, $this->fakeConfigPath);

        $this->assertTrue($verifier->verify('correct-password', 'known-hash', 'known-salt'));
    }

    public function test_verify_returns_false_when_the_node_script_reports_no_match(): void
    {
        $verifier = new FirebaseScryptVerifier($this->fakeVerifierPath, $this->fakeConfigPath);

        $this->assertFalse($verifier->verify('wrong-password', 'known-hash', 'known-salt'));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=FirebaseScryptVerifierTest`
Expected: FAIL — `App\Services\FirebaseScryptVerifier` doesn't exist.

- [ ] **Step 3: Implement the service + config**

```php
<?php
// backend/app/Services/FirebaseScryptVerifier.php

namespace App\Services;

use Symfony\Component\Process\Process;

class FirebaseScryptVerifier
{
    public function __construct(
        private readonly string $nodeVerifierPath,
        private readonly string $hashConfigPath,
    ) {
    }

    public function verify(string $plainPassword, string $base64Hash, string $base64Salt): bool
    {
        $process = new Process(['node', $this->nodeVerifierPath, $this->hashConfigPath]);
        $process->setInput(json_encode([
            'password' => $plainPassword,
            'hash' => $base64Hash,
            'salt' => $base64Salt,
        ], JSON_THROW_ON_ERROR));
        $process->run();

        return $process->getExitCode() === 0;
    }
}
```

Append to `backend/config/services.php` inside the returned array:

```php
    'firebase_scrypt' => [
        'node_verifier_path' => base_path('scripts/firebase-auth-verify/verify.js'),
        'hash_config_path' => env('FIREBASE_HASH_CONFIG_PATH', storage_path('app/firestore-snapshot/hash-config.json')),
    ],
```

Register it in `backend/app/Providers/AppServiceProvider.php` inside `register()`:

```php
use App\Services\FirebaseScryptVerifier;

$this->app->singleton(FirebaseScryptVerifier::class, function () {
    return new FirebaseScryptVerifier(
        config('services.firebase_scrypt.node_verifier_path'),
        config('services.firebase_scrypt.hash_config_path'),
    );
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=FirebaseScryptVerifierTest`
Expected: PASS, both assertions green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirebaseScryptVerifier.php backend/config/services.php \
        backend/app/Providers/AppServiceProvider.php backend/tests/Feature/FirebaseScryptVerifierTest.php
git commit -m "feat: add FirebaseScryptVerifier service for legacy password checks"
```

---

### Task 6: Wire legacy-password verification into `AuthController::login()`

**Files:**
- Modify: `backend/app/Http/Controllers/Api/AuthController.php:89-115` (the existing `login()` method)
- Modify: `backend/tests/Feature/AuthTest.php`

**Interfaces:**
- Consumes: `FirebaseScryptVerifier::verify()` from Task 5.
- Behavior change: if a `User` has `legacy_password_hash` set and no usable `password`, `login()` verifies via `FirebaseScryptVerifier` instead of `Hash::check()`. On success, it rehashes the plaintext into `password` via `Hash::make()` and clears the legacy columns. On failure, the response is identical to today's "credentials incorrect" — no new behavior is observable to a user typing the wrong password.

- [ ] **Step 1: Write a failing test for both branches**

```php
// Add to backend/tests/Feature/AuthTest.php, inside class AuthTest

use App\Services\FirebaseScryptVerifier;
use Illuminate\Support\Facades\Hash;

    public function test_login_succeeds_for_a_migrated_account_via_legacy_password_verification(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $this->mock(FirebaseScryptVerifier::class, function ($mock) {
            $mock->shouldReceive('verify')
                ->once()
                ->with('their-old-password', 'stored-hash', 'stored-salt')
                ->andReturn(true);
        });

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'their-old-password',
        ]);

        $response->assertOk();
        $user->refresh();
        $this->assertNull($user->legacy_password_hash);
        $this->assertNull($user->legacy_password_salt);
        $this->assertTrue(Hash::check('their-old-password', $user->password));
    }

    public function test_login_fails_for_a_migrated_account_with_the_wrong_password(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $this->mock(FirebaseScryptVerifier::class, function ($mock) {
            $mock->shouldReceive('verify')->once()->andReturn(false);
        });

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'wrong-password',
        ]);

        $response->assertStatus(401);
        $user->refresh();
        $this->assertNotNull($user->legacy_password_hash, 'legacy hash must survive a failed attempt');
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=AuthTest`
Expected: FAIL on the two new tests — `login()` doesn't check `legacy_password_hash` yet, and today's code calls `Hash::check(..., null)` which would error or reject.

- [ ] **Step 3: Modify `login()`**

In `backend/app/Http/Controllers/Api/AuthController.php`, replace the existing credential check inside `login()`:

```php
        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'message' => 'The provided credentials are incorrect.',
            ], Response::HTTP_UNAUTHORIZED);
        }
```

with:

```php
        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! $this->passwordMatches($user, $validated['password'])) {
            return response()->json([
                'message' => 'The provided credentials are incorrect.',
            ], Response::HTTP_UNAUTHORIZED);
        }
```

Add the constructor dependency and the new private method (near the other private helpers, e.g. below `googleAudienceIds()`):

```php
use App\Services\FirebaseScryptVerifier;

    public function __construct(
        private readonly UserScoreService $userScoreService,
        private readonly FirebaseScryptVerifier $firebaseScryptVerifier,
    ) {
    }

    private function passwordMatches(User $user, string $plainPassword): bool
    {
        if ($user->legacy_password_hash !== null) {
            $verified = $this->firebaseScryptVerifier->verify(
                $plainPassword,
                $user->legacy_password_hash,
                $user->legacy_password_salt ?? '',
            );

            if (! $verified) {
                return false;
            }

            $user->password = Hash::make($plainPassword);
            $user->legacy_password_hash = null;
            $user->legacy_password_salt = null;
            $user->save();

            return true;
        }

        return $user->password !== null && Hash::check($plainPassword, $user->password);
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=AuthTest`
Expected: PASS, including all pre-existing `AuthTest` cases (the change must not break normal bcrypt login).

- [ ] **Step 5: Commit**

```bash
git add backend/app/Http/Controllers/Api/AuthController.php backend/tests/Feature/AuthTest.php
git commit -m "feat: verify legacy Firebase passwords on login and lazily rehash to bcrypt"
```

---

### Task 7: Snapshot reader + import report infrastructure

**Files:**
- Create: `backend/app/Services/FirestoreImport/SnapshotReader.php`
- Create: `backend/app/Services/FirestoreImport/ImportReport.php`
- Create: `backend/app/Services/FirestoreImport/DryRunAbort.php`
- Test: `backend/tests/Feature/FirestoreImport/SnapshotReaderTest.php`
- Test: `backend/tests/Feature/FirestoreImport/ImportReportTest.php`

**Interfaces:**
- Produces: `SnapshotReader::collection(string $name): array<int, array{id: string, data: array}>`, `SnapshotReader::collectionGroup(string $name): array<int, array{id: string, path: string, data: array}>`, `SnapshotReader::authUsers(): array<int, array<string, mixed>>`.
- Produces: `ImportReport::increment(string $collection, string $bucket): void`, `ImportReport::skip(string $collection, string $sourceId, string $reason): void`, `ImportReport::counts(): array`, `ImportReport::skippedRecords(): array`, `ImportReport::summary(): string`.
- Consumed by: every Importer (Tasks 9–14) and the command (Task 8).

- [ ] **Step 1: Write failing tests for both classes**

```php
<?php
// backend/tests/Feature/FirestoreImport/SnapshotReaderTest.php

namespace Tests\Feature\FirestoreImport;

use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class SnapshotReaderTest extends TestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/snapshot-reader-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_collection_reads_a_plain_collection_file(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid1', 'data' => ['email' => 'a@example.com']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['id' => 'uid1', 'data' => ['email' => 'a@example.com']],
        ], $reader->collection('users'));
    }

    public function test_collection_returns_empty_array_when_file_is_missing(): void
    {
        $reader = new SnapshotReader($this->dir);

        $this->assertSame([], $reader->collection('does_not_exist'));
    }

    public function test_collection_group_reads_a_group_file_with_paths(): void
    {
        File::put("{$this->dir}/_group_tasks.json", json_encode([
            ['id' => 't1', 'path' => 'goals/g1/tasks/t1', 'data' => ['title' => 'Do it']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['id' => 't1', 'path' => 'goals/g1/tasks/t1', 'data' => ['title' => 'Do it']],
        ], $reader->collectionGroup('tasks'));
    }

    public function test_auth_users_reads_the_users_key_from_the_export_file(): void
    {
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid1', 'email' => 'a@example.com']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['localId' => 'uid1', 'email' => 'a@example.com'],
        ], $reader->authUsers());
    }
}
```

```php
<?php
// backend/tests/Feature/FirestoreImport/ImportReportTest.php

namespace Tests\Feature\FirestoreImport;

use App\Services\FirestoreImport\ImportReport;
use Tests\TestCase;

class ImportReportTest extends TestCase
{
    public function test_increment_accumulates_counts_per_collection_and_bucket(): void
    {
        $report = new ImportReport();
        $report->increment('users', 'created');
        $report->increment('users', 'created');
        $report->increment('users', 'updated');

        $this->assertSame(['created' => 2, 'updated' => 1], $report->counts()['users']);
    }

    public function test_skip_records_the_reason_and_increments_a_skipped_bucket(): void
    {
        $report = new ImportReport();
        $report->skip('goals', 'g1', 'no matching user');

        $this->assertSame([['goals', 'g1', 'no matching user']], $report->skippedRecords());
        $this->assertSame(1, $report->counts()['goals']['skipped']);
    }

    public function test_summary_includes_counts_and_skipped_lines(): void
    {
        $report = new ImportReport();
        $report->increment('users', 'created');
        $report->skip('goals', 'g1', 'no matching user');

        $summary = $report->summary();

        $this->assertStringContainsString('users: created=1', $summary);
        $this->assertStringContainsString('SKIPPED goals/g1: no matching user', $summary);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && php artisan test --filter=SnapshotReaderTest && php artisan test --filter=ImportReportTest`
Expected: FAIL — neither class exists.

- [ ] **Step 3: Implement both classes**

```php
<?php
// backend/app/Services/FirestoreImport/SnapshotReader.php

namespace App\Services\FirestoreImport;

class SnapshotReader
{
    public function __construct(private readonly string $basePath)
    {
    }

    /** @return array<int, array{id: string, data: array}> */
    public function collection(string $name): array
    {
        return $this->readJsonArray("{$this->basePath}/{$name}.json");
    }

    /** @return array<int, array{id: string, path: string, data: array}> */
    public function collectionGroup(string $name): array
    {
        return $this->readJsonArray("{$this->basePath}/_group_{$name}.json");
    }

    /** @return array<int, array<string, mixed>> */
    public function authUsers(): array
    {
        $path = "{$this->basePath}/auth-users.json";
        if (! file_exists($path)) {
            return [];
        }
        $decoded = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);

        return $decoded['users'] ?? [];
    }

    private function readJsonArray(string $path): array
    {
        if (! file_exists($path)) {
            return [];
        }

        return json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR) ?? [];
    }
}
```

```php
<?php
// backend/app/Services/FirestoreImport/ImportReport.php

namespace App\Services\FirestoreImport;

class ImportReport
{
    /** @var array<string, array<string, int>> */
    private array $counts = [];

    /** @var array<int, array{0: string, 1: string, 2: string}> */
    private array $skipped = [];

    public function increment(string $collection, string $bucket): void
    {
        $this->counts[$collection][$bucket] = ($this->counts[$collection][$bucket] ?? 0) + 1;
    }

    public function skip(string $collection, string $sourceId, string $reason): void
    {
        $this->skipped[] = [$collection, $sourceId, $reason];
        $this->increment($collection, 'skipped');
    }

    /** @return array<string, array<string, int>> */
    public function counts(): array
    {
        return $this->counts;
    }

    /** @return array<int, array{0: string, 1: string, 2: string}> */
    public function skippedRecords(): array
    {
        return $this->skipped;
    }

    public function summary(): string
    {
        $lines = [];
        foreach ($this->counts as $collection => $buckets) {
            $parts = [];
            foreach ($buckets as $bucket => $count) {
                $parts[] = "{$bucket}={$count}";
            }
            $lines[] = "{$collection}: ".implode(', ', $parts);
        }
        foreach ($this->skipped as [$collection, $sourceId, $reason]) {
            $lines[] = "  SKIPPED {$collection}/{$sourceId}: {$reason}";
        }

        return implode(PHP_EOL, $lines);
    }
}
```

```php
<?php
// backend/app/Services/FirestoreImport/DryRunAbort.php

namespace App\Services\FirestoreImport;

class DryRunAbort extends \RuntimeException
{
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && php artisan test --filter=SnapshotReaderTest && php artisan test --filter=ImportReportTest`
Expected: PASS, all assertions green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/SnapshotReader.php \
        backend/app/Services/FirestoreImport/ImportReport.php \
        backend/app/Services/FirestoreImport/DryRunAbort.php \
        backend/tests/Feature/FirestoreImport/SnapshotReaderTest.php \
        backend/tests/Feature/FirestoreImport/ImportReportTest.php
git commit -m "feat: add snapshot reader and import report for Firestore migration"
```

---

### Task 8: `firestore:import` Artisan command skeleton

**Files:**
- Create: `backend/app/Console/Commands/ImportFirestoreData.php`
- Test: `backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php`

**Interfaces:**
- Produces: `php artisan firestore:import {--path=} {--dry-run}`. Default `--path` is `storage/app/firestore-snapshot`.
- Consumes: an ordered list of Importer instances (empty in this task — Task 15 wires the real ones in). Each Importer must expose `public function import(bool $dryRun): void`.

This task builds the orchestration shell — dry-run transaction handling, path resolution, summary printing — with zero real importers registered yet, so it's independently testable. Task 15 adds the real importer list once all of them exist.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php

namespace Tests\Feature\FirestoreImport;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class ImportFirestoreDataCommandTest extends TestCase
{
    use RefreshDatabase;

    public function test_command_reports_missing_snapshot_path(): void
    {
        $this->artisan('firestore:import', ['--path' => '/nonexistent/path'])
            ->expectsOutputToContain('Snapshot path does not exist')
            ->assertExitCode(1);
    }

    public function test_command_runs_and_prints_a_summary_for_an_empty_snapshot(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-test-'.uniqid();
        File::ensureDirectoryExists($dir);

        $this->artisan('firestore:import', ['--path' => $dir])
            ->expectsOutputToContain('Import complete')
            ->assertExitCode(0);

        File::deleteDirectory($dir);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=ImportFirestoreDataCommandTest`
Expected: FAIL — the `firestore:import` command doesn't exist.

- [ ] **Step 3: Implement the command**

```php
<?php
// backend/app/Console/Commands/ImportFirestoreData.php

namespace App\Console\Commands;

use App\Services\FirestoreImport\DryRunAbort;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class ImportFirestoreData extends Command
{
    protected $signature = 'firestore:import {--path=} {--dry-run}';

    protected $description = 'Import a Firestore snapshot (see scripts/firestore-export) into Postgres.';

    public function handle(): int
    {
        $path = $this->option('path') ?: storage_path('app/firestore-snapshot');

        if (! is_dir($path)) {
            $this->error("Snapshot path does not exist: {$path}");

            return self::FAILURE;
        }

        $dryRun = (bool) $this->option('dry-run');
        $reader = new SnapshotReader($path);
        $report = new ImportReport();

        foreach ($this->importers($reader, $report) as $importer) {
            try {
                DB::transaction(function () use ($importer, $dryRun): void {
                    $importer->import($dryRun);
                    if ($dryRun) {
                        throw new DryRunAbort();
                    }
                });
            } catch (DryRunAbort) {
                // Expected for --dry-run: the transaction rolled back on purpose.
            }
        }

        $this->line($dryRun ? 'DRY RUN — no changes were committed.' : 'Import complete.');
        $this->line($report->summary());

        return self::SUCCESS;
    }

    /** @return array<int, object{import: callable(bool): void}> */
    private function importers(SnapshotReader $reader, ImportReport $report): array
    {
        // Populated in Task 15 once every Importer class exists.
        return [];
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=ImportFirestoreDataCommandTest`
Expected: PASS, both assertions green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Console/Commands/ImportFirestoreData.php \
        backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php
git commit -m "feat: add firestore:import command skeleton with dry-run support"
```

---

### Task 9: `UserImporter` (users + coaches + Firebase Auth export)

**Files:**
- Create: `backend/app/Services/FirestoreImport/UserImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/UserImporterTest.php`

**Interfaces:**
- Produces: `UserImporter::import(bool $dryRun): void` — matches the shape every other Importer in this plan follows.
- Consumes: `SnapshotReader::collection('users')`, `SnapshotReader::collection('coaches')`, `SnapshotReader::authUsers()`.
- Produces (for downstream tasks): every migrated `User` row has `firebase_uid` set — Tasks 10–14 all resolve foreign keys by looking up `User::where('firebase_uid', $uid)`.

Driven by the Auth export (not the Firestore `users` collection) so every account that could ever log in gets migrated, even the rare one missing a Firestore profile doc. Matches an existing Postgres user by `firebase_uid` first, then by `email` (covers the case where someone already exists in Postgres pre-migration), then creates fresh.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/UserImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\UserImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class UserImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/user-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_password_account_with_profile_and_hash(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid-1', 'data' => ['username' => 'Jane', 'profilePic' => 'https://x/jane.png', 'activeCompanyId' => 'co-1']],
        ]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [[
                'localId' => 'uid-1',
                'email' => 'jane@example.com',
                'emailVerified' => true,
                'passwordHash' => 'base64hash',
                'salt' => 'base64salt',
                'providerUserInfo' => [['providerId' => 'password']],
            ]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-1')->first();
        $this->assertNotNull($user);
        $this->assertSame('jane@example.com', $user->email);
        $this->assertSame('Jane', $user->name);
        $this->assertSame('https://x/jane.png', $user->profile_pic);
        $this->assertSame('co-1', $user->active_company_id);
        $this->assertNotNull($user->email_verified_at);
        $this->assertSame('base64hash', $user->legacy_password_hash);
        $this->assertSame('base64salt', $user->legacy_password_salt);
    }

    public function test_merges_a_coaches_doc_onto_the_matching_user(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid-2', 'data' => ['username' => 'Coach Original']],
        ]));
        File::put("{$this->dir}/coaches.json", json_encode([
            ['id' => 'uid-2', 'data' => ['fullName' => 'Coach Full Name', 'bio' => 'Fitness coach for 10 years']],
        ]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-2', 'email' => 'coach@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-2')->first();
        $this->assertSame('Coach Full Name', $user->name);
        $this->assertSame('Fitness coach for 10 years', $user->bio);
        $this->assertTrue((bool) $user->is_coach);
        $this->assertSame('coach', $user->role);
    }

    public function test_apple_sign_in_provider_sets_apple_user_id_and_no_password_columns(): void
    {
        File::put("{$this->dir}/users.json", json_encode([]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [[
                'localId' => 'uid-3',
                'email' => 'apple.user@example.com',
                'emailVerified' => true,
                'providerUserInfo' => [['providerId' => 'apple.com', 'rawId' => 'apple-sub-123']],
            ]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-3')->first();
        $this->assertSame('apple-sub-123', $user->apple_user_id);
        $this->assertNull($user->legacy_password_hash);
    }

    public function test_rerunning_the_importer_updates_instead_of_duplicating(): void
    {
        File::put("{$this->dir}/users.json", json_encode([['id' => 'uid-4', 'data' => ['username' => 'Original']]]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-4', 'email' => 'rerun@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);
        $importer->import(false);

        $this->assertSame(1, User::where('firebase_uid', 'uid-4')->count());
    }

    public function test_skips_an_auth_record_missing_a_local_id(): void
    {
        File::put("{$this->dir}/users.json", json_encode([]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode(['users' => [['email' => 'no-uid@example.com']]]));

        $report = new ImportReport();
        $importer = new UserImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, User::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=UserImporterTest`
Expected: FAIL — `UserImporter` doesn't exist.

- [ ] **Step 3: Implement `UserImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/UserImporter.php

namespace App\Services\FirestoreImport;

use App\Models\User;
use Illuminate\Support\Carbon;

class UserImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        $firestoreUsers = $this->keyById($this->reader->collection('users'));
        $coaches = $this->keyById($this->reader->collection('coaches'));

        foreach ($this->reader->authUsers() as $authUser) {
            $uid = $authUser['localId'] ?? null;
            $email = $authUser['email'] ?? null;

            if (! is_string($uid) || $uid === '' || ! is_string($email) || $email === '') {
                $this->report->skip('users', (string) ($uid ?? 'unknown'), 'auth export record missing localId or email');

                continue;
            }

            $profile = $firestoreUsers[$uid] ?? [];
            $coach = $coaches[$uid] ?? null;

            $user = User::where('firebase_uid', $uid)->first()
                ?? User::where('email', $email)->first()
                ?? new User();
            $wasNew = ! $user->exists;

            $user->firebase_uid = $uid;
            $user->email = $email;
            $user->name = $coach['fullName'] ?? $profile['username'] ?? $profile['name'] ?? ($authUser['displayName'] ?? $email);
            $user->profile_pic = $profile['profilePic'] ?? ($authUser['photoUrl'] ?? $user->profile_pic);
            $user->active_company_id = $profile['activeCompanyId'] ?? $profile['companyId'] ?? $user->active_company_id;
            $user->company_id = $profile['companyId'] ?? $user->company_id;

            if ($wasNew) {
                $user->role = 'user';
            }

            if ($coach !== null) {
                $user->role = 'coach';
                $user->is_coach = true;
                if (isset($coach['bio'])) {
                    $user->bio = $coach['bio'];
                }
            }

            $user->email_verified_at = ($authUser['emailVerified'] ?? false) ? Carbon::now() : null;

            $appleProvider = collect($authUser['providerUserInfo'] ?? [])->firstWhere('providerId', 'apple.com');
            if ($appleProvider !== null && ! empty($appleProvider['rawId'])) {
                $user->apple_user_id = $appleProvider['rawId'];
            }

            $passwordProvider = collect($authUser['providerUserInfo'] ?? [])->firstWhere('providerId', 'password');
            if ($passwordProvider !== null && ! empty($authUser['passwordHash'])) {
                $user->legacy_password_hash = $authUser['passwordHash'];
                $user->legacy_password_salt = $authUser['salt'] ?? null;
            }

            $user->save();

            $this->report->increment('users', $wasNew ? 'created' : 'updated');
        }
    }

    /**
     * @param  array<int, array{id: string, data: array}>  $records
     * @return array<string, array<string, mixed>>
     */
    private function keyById(array $records): array
    {
        $byId = [];
        foreach ($records as $record) {
            $byId[$record['id']] = $record['data'];
        }

        return $byId;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=UserImporterTest`
Expected: PASS, all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/UserImporter.php backend/tests/Feature/FirestoreImport/UserImporterTest.php
git commit -m "feat: add UserImporter merging Firestore users/coaches with Firebase Auth export"
```

---

### Task 10: `CoachRelationshipImporter` (coach_groups, coach_requests, coach_mentees)

**Files:**
- Create: `backend/app/Services/FirestoreImport/CoachRelationshipImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/CoachRelationshipImporterTest.php`

**Interfaces:**
- Produces: `CoachRelationshipImporter::import(bool $dryRun): void`.
- Consumes: `SnapshotReader::collection('coach_groups')`, `SnapshotReader::collection('coach_requests')`, `SnapshotReader::collection('users')` (re-read here for `coachIds`/`coachId`, since those fields live on the `users` collection, not a dedicated relationship collection). Requires `UserImporter` to have already run (Task 9) — foreign keys are resolved via `User::firebase_uid`.

`CoachManagementController.php:337-370` and `:647-671` (read during planning) confirmed `coach_mentees.coach_id`/`mentee_id` store the **Postgres integer user ID cast to string** — not the Firebase UID — and that a mentee's group membership is determined by `coach_mentees.group_id` pointing at `coach_groups.id`, not by the `coach_groups.member_ids` column (which the live app now only reads for a legacy fallback display, never as the source of truth). This importer follows that same convention: it establishes base coach↔mentee pairs from each user's `coachIds`/`coachId`, then attaches group membership from each `coach_groups` doc's historical `memberIds` array, then recomputes `member_count` — it does not trust the historical `memberCount` field.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/CoachRelationshipImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use App\Services\FirestoreImport\CoachRelationshipImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class CoachRelationshipImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/coach-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_group_request_and_synthesizes_mentee_relationship_with_group(): void
    {
        $coach = User::factory()->create(['firebase_uid' => 'coach-uid', 'is_coach' => true]);
        $mentee = User::factory()->create(['firebase_uid' => 'mentee-uid']);

        File::put("{$this->dir}/coach_groups.json", json_encode([
            ['id' => 'group-1', 'data' => ['coachId' => 'coach-uid', 'name' => 'Morning Crew', 'memberIds' => ['mentee-uid'], 'memberCount' => 1]],
        ]));
        File::put("{$this->dir}/coach_requests.json", json_encode([
            ['id' => 'req-1', 'data' => [
                'coachId' => 'coach-uid', 'menteeId' => 'mentee-uid', 'menteeName' => 'Mentee Name',
                'menteeEmail' => 'mentee@example.com', 'status' => 'accepted', 'applyingAs' => 'mentee',
            ]],
        ]));
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'mentee-uid', 'data' => ['coachIds' => ['coach-uid']]],
        ]));

        $importer = new CoachRelationshipImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $group = CoachGroup::where('firestore_id', 'group-1')->first();
        $this->assertNotNull($group);
        $this->assertSame((string) $coach->id, (string) $group->coach_id);
        $this->assertSame(1, $group->member_count);

        $request = CoachRequest::where('firestore_id', 'req-1')->first();
        $this->assertNotNull($request);
        $this->assertSame('accepted', $request->status);

        $relation = CoachMentee::where('coach_id', (string) $coach->id)->where('mentee_id', (string) $mentee->id)->first();
        $this->assertNotNull($relation);
        $this->assertSame($group->id, $relation->group_id);
        $this->assertSame('Morning Crew', $relation->group_name);
    }

    public function test_skips_a_group_with_no_matching_coach(): void
    {
        File::put("{$this->dir}/coach_groups.json", json_encode([
            ['id' => 'group-1', 'data' => ['coachId' => 'missing-uid', 'name' => 'Orphan Group']],
        ]));
        File::put("{$this->dir}/coach_requests.json", json_encode([]));
        File::put("{$this->dir}/users.json", json_encode([]));

        $report = new ImportReport();
        $importer = new CoachRelationshipImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, CoachGroup::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=CoachRelationshipImporterTest`
Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement `CoachRelationshipImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/CoachRelationshipImporter.php

namespace App\Services\FirestoreImport;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use Illuminate\Support\Str;

class CoachRelationshipImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('coach_groups') as $record) {
            $this->importGroup($record['id'], $record['data']);
        }
        foreach ($this->reader->collection('coach_requests') as $record) {
            $this->importRequest($record['id'], $record['data']);
        }

        $this->synthesizeBaseRelationships();
        $this->attachGroupMembership();
        $this->recomputeGroupCounts();
    }

    private function importGroup(string $firestoreId, array $data): void
    {
        $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
        if ($coachId === null) {
            $this->report->skip('coach_groups', $firestoreId, 'no matching coach for coachId '.($data['coachId'] ?? 'null'));

            return;
        }

        $group = CoachGroup::where('firestore_id', $firestoreId)->first() ?? new CoachGroup(['id' => (string) Str::uuid()]);
        $group->firestore_id = $firestoreId;
        $group->coach_id = (string) $coachId;
        $group->name = $data['name'] ?? '';
        $group->member_ids = $data['memberIds'] ?? [];
        $group->member_count = 0; // recomputed in recomputeGroupCounts() after synthesis
        $group->save();

        $this->report->increment('coach_groups', $group->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importRequest(string $firestoreId, array $data): void
    {
        $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
        $menteeId = User::where('firebase_uid', $data['menteeId'] ?? null)->value('id');
        if ($coachId === null || $menteeId === null) {
            $this->report->skip('coach_requests', $firestoreId, 'missing coach or mentee match');

            return;
        }

        $request = CoachRequest::where('firestore_id', $firestoreId)->first() ?? new CoachRequest(['id' => (string) Str::uuid()]);
        $request->firestore_id = $firestoreId;
        $request->coach_id = (string) $coachId;
        $request->coach_name = $data['coachName'] ?? null;
        $request->coach_email = $data['coachEmail'] ?? null;
        $request->mentee_id = (string) $menteeId;
        $request->mentee_name = $data['menteeName'] ?? null;
        $request->mentee_email = $data['menteeEmail'] ?? null;
        $request->applicant_role = $data['applicantRole'] ?? null;
        $request->applicant_is_coach = $data['applicantIsCoach'] ?? false;
        $request->applying_as = $data['applyingAs'] ?? 'mentee';
        $request->status = $data['status'] ?? 'pending';
        $request->save();

        $this->report->increment('coach_requests', $request->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function synthesizeBaseRelationships(): void
    {
        foreach ($this->reader->collection('users') as $record) {
            $data = $record['data'];
            $coachUids = $data['coachIds'] ?? (isset($data['coachId']) ? [$data['coachId']] : []);
            if (empty($coachUids)) {
                continue;
            }

            $mentee = User::where('firebase_uid', $record['id'])->first();
            if ($mentee === null) {
                continue;
            }

            foreach ($coachUids as $coachUid) {
                $coach = User::where('firebase_uid', $coachUid)->first();
                if ($coach === null) {
                    $this->report->skip('coach_mentees', $record['id'], "no matching coach for coachId {$coachUid}");

                    continue;
                }

                CoachMentee::query()->firstOrCreate(
                    ['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id],
                    ['mentee_name' => $mentee->name, 'mentee_email' => $mentee->email],
                );
                $this->report->increment('coach_mentees', 'synced');
            }
        }
    }

    private function attachGroupMembership(): void
    {
        foreach ($this->reader->collection('coach_groups') as $record) {
            $data = $record['data'];
            $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
            $group = CoachGroup::where('firestore_id', $record['id'])->first();
            if ($coachId === null || $group === null) {
                continue;
            }

            foreach (($data['memberIds'] ?? []) as $memberUid) {
                $menteeId = User::where('firebase_uid', $memberUid)->value('id');
                if ($menteeId === null) {
                    continue;
                }

                CoachMentee::query()
                    ->where('coach_id', (string) $coachId)
                    ->where('mentee_id', (string) $menteeId)
                    ->update(['group_id' => $group->id, 'group_name' => $group->name]);
            }
        }
    }

    private function recomputeGroupCounts(): void
    {
        CoachGroup::query()->whereNotNull('firestore_id')->each(function (CoachGroup $group): void {
            $group->member_count = CoachMentee::where('group_id', $group->id)->count();
            $group->save();
        });
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=CoachRelationshipImporterTest`
Expected: PASS, both tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/CoachRelationshipImporter.php \
        backend/tests/Feature/FirestoreImport/CoachRelationshipImporterTest.php
git commit -m "feat: add CoachRelationshipImporter for coach groups, requests, and mentee links"
```

---

### Task 11: `GoalImporter` (goals + tasks/updates/comments/merits)

**Files:**
- Create: `backend/app/Services/FirestoreImport/GoalImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/GoalImporterTest.php`

**Interfaces:**
- Produces: `GoalImporter::import(bool $dryRun): void`.
- Consumes: `SnapshotReader::collection('goals')`, `SnapshotReader::collectionGroup('tasks'|'updates'|'comments'|'merits')`. For `comments`, only records whose `path` starts with `goals/` are handled here — `notes/{id}/comments` belongs to `NotesImporter` (Task 12), since Firestore uses the same subcollection name (`comments`) under two different parents.
- Known, disclosed gap: the historical `kind` field on merit-log entries (`'extra'` marker for "go extra mile" logs) has no column in `goal_merits` and is dropped — logged via `ImportReport::skip()` as an informational note, not silently discarded.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/GoalImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\Goal;
use App\Models\GoalComment;
use App\Models\GoalMerit;
use App\Models\GoalTask;
use App\Models\GoalUpdate;
use App\Models\User;
use App\Services\FirestoreImport\GoalImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class GoalImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/goal-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_goal_and_its_full_subcollection_family(): void
    {
        $owner = User::factory()->create(['firebase_uid' => 'owner-uid']);

        File::put("{$this->dir}/goals.json", json_encode([
            ['id' => 'goal-1', 'data' => [
                'userId' => 'owner-uid', 'title' => 'Run a marathon', 'category' => 'PERSONAL',
                'status' => 'IN_PROGRESS', 'goalType' => 'MILESTONE', 'direction' => 'GAIN',
                'targetPeriod' => 'WEEKLY', 'targetValue' => 26.2, 'currentValue' => 10, 'progress' => 40,
                'startDate' => '2025-01-01', 'targetDate' => '2025-06-01',
            ]],
        ]));
        File::put("{$this->dir}/_group_tasks.json", json_encode([
            ['id' => 'task-1', 'path' => 'goals/goal-1/tasks/task-1', 'data' => ['title' => 'Buy shoes', 'status' => 'DONE', 'isComplete' => true, 'sortOrder' => 0]],
        ]));
        File::put("{$this->dir}/_group_updates.json", json_encode([
            ['id' => 'upd-1', 'path' => 'goals/goal-1/updates/upd-1', 'data' => ['authorId' => 'owner-uid', 'progressFrom' => 10, 'progressTo' => 40, 'statusFrom' => 'NOT_STARTED', 'statusTo' => 'IN_PROGRESS']],
        ]));
        File::put("{$this->dir}/_group_comments.json", json_encode([
            ['id' => 'cmt-1', 'path' => 'goals/goal-1/comments/cmt-1', 'data' => ['authorId' => 'owner-uid', 'body' => 'Great progress!', 'isPrivate' => false]],
            ['id' => 'note-cmt-1', 'path' => 'notes/note-9/comments/note-cmt-1', 'data' => ['userId' => 'owner-uid', 'content' => 'not a goal comment']],
        ]));
        File::put("{$this->dir}/_group_merits.json", json_encode([
            ['id' => 'merit-1', 'path' => 'goals/goal-1/merits/merit-1', 'data' => ['date' => '2025-02-01', 'amount' => 3.1]],
        ]));

        $importer = new GoalImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $goal = Goal::where('firestore_id', 'goal-1')->first();
        $this->assertNotNull($goal);
        $this->assertSame($owner->id, $goal->user_id);
        $this->assertSame('Run a marathon', $goal->title);

        $this->assertSame(1, GoalTask::where('goal_id', $goal->id)->count());
        $this->assertSame(1, GoalUpdate::where('goal_id', $goal->id)->count());
        $this->assertSame(1, GoalComment::where('goal_id', $goal->id)->count());
        $this->assertSame(0, GoalComment::where('firestore_id', 'note-cmt-1')->count(), 'note comments must not leak into goal_comments');

        $merit = GoalMerit::where('firestore_id', 'merit-1')->first();
        $this->assertNotNull($merit);
        $this->assertSame($goal->user_id, $merit->user_id);
    }

    public function test_skips_a_goal_with_no_matching_user(): void
    {
        File::put("{$this->dir}/goals.json", json_encode([
            ['id' => 'goal-2', 'data' => ['userId' => 'missing-uid', 'title' => 'Orphan goal']],
        ]));
        File::put("{$this->dir}/_group_tasks.json", json_encode([]));
        File::put("{$this->dir}/_group_updates.json", json_encode([]));
        File::put("{$this->dir}/_group_comments.json", json_encode([]));
        File::put("{$this->dir}/_group_merits.json", json_encode([]));

        $report = new ImportReport();
        $importer = new GoalImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, Goal::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=GoalImporterTest`
Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement `GoalImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/GoalImporter.php

namespace App\Services\FirestoreImport;

use App\Models\Goal;
use App\Models\GoalComment;
use App\Models\GoalMerit;
use App\Models\GoalTask;
use App\Models\GoalUpdate;
use App\Models\User;
use Illuminate\Support\Str;

class GoalImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('goals') as $record) {
            $this->importGoal($record['id'], $record['data']);
        }

        foreach ($this->reader->collectionGroup('tasks') as $record) {
            $this->withParentGoal('goal_tasks', $record, fn (string $goalId) => $this->importTask($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('updates') as $record) {
            $this->withParentGoal('goal_updates', $record, fn (string $goalId) => $this->importUpdate($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('comments') as $record) {
            if (! str_starts_with($record['path'], 'goals/')) {
                continue; // 'notes/{id}/comments' belongs to NotesImporter
            }
            $this->withParentGoal('goal_comments', $record, fn (string $goalId) => $this->importComment($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('merits') as $record) {
            $this->withParentGoal('goal_merits', $record, fn (string $goalId) => $this->importMerit($goalId, $record['data'], $record['id']));
            if (isset($record['data']['kind'])) {
                $this->report->skip('goal_merits.kind', $record['id'], "dropped historical 'kind' marker ({$record['data']['kind']}) — no column exists for it");
            }
        }
    }

    private function withParentGoal(string $collection, array $record, callable $handler): void
    {
        $segments = explode('/', $record['path']);
        $firestoreGoalId = $segments[1] ?? null;
        if ($firestoreGoalId === null) {
            $this->report->skip($collection, $record['id'], 'could not parse parent goal id from path '.$record['path']);

            return;
        }
        $handler($firestoreGoalId);
    }

    private function importGoal(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($userId === null) {
            $this->report->skip('goals', $firestoreId, 'no matching user for userId '.($data['userId'] ?? 'null'));

            return;
        }

        $goal = Goal::where('firestore_id', $firestoreId)->first() ?? new Goal(['id' => (string) Str::uuid()]);
        $goal->firestore_id = $firestoreId;
        $goal->user_id = $userId;
        $goal->company_id = $data['companyId'] ?? null;
        $goal->category = $data['category'] ?? 'PERSONAL';
        $goal->title = $data['title'] ?? '';
        $goal->description = $data['description'] ?? null;
        $goal->notes = $data['notes'] ?? null;
        $goal->status = $data['status'] ?? 'NOT_STARTED';
        $goal->goal_type = $data['goalType'] ?? 'MILESTONE';
        $goal->direction = $data['direction'] ?? 'GAIN';
        $goal->target_value = $data['targetValue'] ?? 0;
        $goal->current_value = $data['currentValue'] ?? 0;
        $goal->unit = $data['unit'] ?? null;
        $goal->target_period = $data['targetPeriod'] ?? 'NONE';
        $goal->start_date = $data['startDate'] ?? null;
        $goal->target_date = $data['targetDate'] ?? null;
        $goal->completed_at = $data['completedAt'] ?? null;
        $goal->progress = $data['progress'] ?? 0;
        $goal->save();

        $this->report->increment('goals', $goal->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importTask(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        if ($goalId === null) {
            $this->report->skip('goal_tasks', $firestoreId, "no matching goal for {$firestoreGoalId}");

            return;
        }

        $task = GoalTask::where('firestore_id', $firestoreId)->first() ?? new GoalTask(['id' => (string) Str::uuid()]);
        $task->firestore_id = $firestoreId;
        $task->goal_id = $goalId;
        $task->title = $data['title'] ?? '';
        $task->status = $data['status'] ?? 'NOT_STARTED';
        $task->is_complete = $data['isComplete'] ?? (($data['status'] ?? null) === 'DONE');
        $task->due_date = $data['dueDate'] ?? null;
        $task->completed_at = $data['completedAt'] ?? null;
        $task->sort_order = $data['sortOrder'] ?? 0;
        $task->save();

        $this->report->increment('goal_tasks', $task->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importUpdate(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        $authorId = User::where('firebase_uid', $data['authorId'] ?? null)->value('id');
        if ($goalId === null || $authorId === null) {
            $this->report->skip('goal_updates', $firestoreId, 'missing goal or author match');

            return;
        }

        $update = GoalUpdate::where('firestore_id', $firestoreId)->first() ?? new GoalUpdate(['id' => (string) Str::uuid()]);
        $update->firestore_id = $firestoreId;
        $update->goal_id = $goalId;
        $update->author_id = $authorId;
        $update->progress_from = $data['progressFrom'] ?? 0;
        $update->progress_to = $data['progressTo'] ?? 0;
        $update->status_from = $data['statusFrom'] ?? 'NOT_STARTED';
        $update->status_to = $data['statusTo'] ?? 'NOT_STARTED';
        $update->note = $data['note'] ?? null;
        $update->save();

        $this->report->increment('goal_updates', $update->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importComment(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        $authorId = User::where('firebase_uid', $data['authorId'] ?? null)->value('id');
        if ($goalId === null || $authorId === null) {
            $this->report->skip('goal_comments', $firestoreId, 'missing goal or author match');

            return;
        }

        $comment = GoalComment::where('firestore_id', $firestoreId)->first() ?? new GoalComment(['id' => (string) Str::uuid()]);
        $comment->firestore_id = $firestoreId;
        $comment->goal_id = $goalId;
        $comment->author_id = $authorId;
        $comment->body = $data['body'] ?? '';
        $comment->is_private = $data['isPrivate'] ?? false;
        $comment->save();

        $this->report->increment('goal_comments', $comment->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importMerit(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goal = Goal::where('firestore_id', $firestoreGoalId)->first();
        if ($goal === null) {
            $this->report->skip('goal_merits', $firestoreId, "no matching goal for {$firestoreGoalId}");

            return;
        }

        $merit = GoalMerit::where('firestore_id', $firestoreId)->first() ?? new GoalMerit(['id' => (string) Str::uuid()]);
        $merit->firestore_id = $firestoreId;
        $merit->goal_id = $goal->id;
        $merit->user_id = $goal->user_id;
        $merit->date = $data['date'] ?? null;
        $merit->amount = $data['amount'] ?? 0;
        $merit->save();

        $this->report->increment('goal_merits', $merit->wasRecentlyCreated ? 'created' : 'updated');
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=GoalImporterTest`
Expected: PASS, both tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/GoalImporter.php backend/tests/Feature/FirestoreImport/GoalImporterTest.php
git commit -m "feat: add GoalImporter for goals and their task/update/comment/merit subcollections"
```

---

### Task 12: `NotesImporter` (notes → community_posts, note comments)

**Files:**
- Create: `backend/app/Services/FirestoreImport/NotesImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/NotesImporterTest.php`

**Interfaces:**
- Produces: `NotesImporter::import(bool $dryRun): void`.
- Consumes: `SnapshotReader::collection('notes')`, `SnapshotReader::collectionGroup('comments')` (only `path` starting with `notes/` — the complementary half of the split GoalImporter also reads from).
- Note: Dart packs the note's `color` as a signed 32-bit ARGB int; `community_posts.color` is `unsignedBigInteger`, so negative values are converted (`+ 4294967296`) to their unsigned equivalent before saving.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/NotesImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\NotesImporter;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class NotesImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/notes-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_note_with_a_negative_packed_color_and_its_comments(): void
    {
        $author = User::factory()->create(['firebase_uid' => 'author-uid']);
        $commenter = User::factory()->create(['firebase_uid' => 'commenter-uid']);

        File::put("{$this->dir}/notes.json", json_encode([
            ['id' => 'note-1', 'data' => [
                'userId' => 'author-uid', 'username' => 'Author', 'title' => 'My journal entry',
                'note' => [['type' => 'text', 'value' => 'hello']], 'color' => -16777216, // 0xFF000000 as a signed 32-bit int
                'category' => 'journal', 'saved' => true, 'createdAt' => '2025-03-01T00:00:00.000Z',
            ]],
        ]));
        File::put("{$this->dir}/_group_comments.json", json_encode([
            ['id' => 'goal-cmt-1', 'path' => 'goals/goal-1/comments/goal-cmt-1', 'data' => ['authorId' => 'author-uid', 'body' => 'not a note comment']],
            ['id' => 'note-cmt-1', 'path' => 'notes/note-1/comments/note-cmt-1', 'data' => ['userId' => 'commenter-uid', 'username' => 'Commenter', 'content' => 'Nice post!']],
        ]));

        $importer = new NotesImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $post = CommunityPost::where('firestore_id', 'note-1')->first();
        $this->assertNotNull($post);
        $this->assertSame($author->id, $post->user_id);
        $this->assertSame(4278190080, $post->color); // 0xFF000000 as unsigned
        $this->assertSame('2025-03-01 00:00:00', $post->created_at->format('Y-m-d H:i:s'));

        $comment = NoteComment::where('firestore_id', 'note-cmt-1')->first();
        $this->assertNotNull($comment);
        $this->assertSame($post->id, $comment->community_post_id);
        $this->assertSame($commenter->id, $comment->user_id);
        $this->assertSame('Nice post!', $comment->comment);
        $this->assertSame(0, NoteComment::where('firestore_id', 'goal-cmt-1')->count(), 'goal comments must not leak into note_comments');
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=NotesImporterTest`
Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement `NotesImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/NotesImporter.php

namespace App\Services\FirestoreImport;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Support\Carbon;

class NotesImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('notes') as $record) {
            $this->importNote($record['id'], $record['data']);
        }

        foreach ($this->reader->collectionGroup('comments') as $record) {
            if (! str_starts_with($record['path'], 'notes/')) {
                continue; // 'goals/{id}/comments' belongs to GoalImporter
            }

            $segments = explode('/', $record['path']);
            $firestoreNoteId = $segments[1] ?? null;
            if ($firestoreNoteId === null) {
                $this->report->skip('note_comments', $record['id'], 'could not parse parent note id from path '.$record['path']);

                continue;
            }
            $this->importComment($firestoreNoteId, $record['data'], $record['id']);
        }
    }

    private function importNote(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($userId === null) {
            $this->report->skip('community_posts', $firestoreId, 'no matching user for userId '.($data['userId'] ?? 'null'));

            return;
        }

        $post = CommunityPost::where('firestore_id', $firestoreId)->first() ?? new CommunityPost();
        $post->firestore_id = $firestoreId;
        $post->user_id = $userId;
        $post->username = $data['username'] ?? '';
        $post->title = $data['title'] ?? '';
        $post->note = $data['note'] ?? [];

        $color = (int) ($data['color'] ?? 0xFFFFFFFF);
        $post->color = $color < 0 ? $color + 4294967296 : $color; // Dart packs ARGB as a signed 32-bit int

        $post->category = $data['category'] ?? '';
        $post->saved = $data['saved'] ?? false;
        $post->company_id = $data['companyId'] ?? null;
        $post->company_code = $data['companyCode'] ?? null;
        $post->company_name = $data['companyName'] ?? null;

        if (! empty($data['createdAt'])) {
            $post->timestamps = false;
            $post->created_at = Carbon::parse($data['createdAt']);
            $post->updated_at = $post->created_at;
        }

        $post->save();

        $this->report->increment('community_posts', $post->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importComment(string $firestoreNoteId, array $data, string $firestoreId): void
    {
        $postId = CommunityPost::where('firestore_id', $firestoreNoteId)->value('id');
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($postId === null || $userId === null) {
            $this->report->skip('note_comments', $firestoreId, 'missing post or user match');

            return;
        }

        $comment = NoteComment::where('firestore_id', $firestoreId)->first() ?? new NoteComment();
        $comment->firestore_id = $firestoreId;
        $comment->community_post_id = $postId;
        $comment->user_id = $userId;
        $comment->username = $data['username'] ?? '';
        $comment->comment = $data['content'] ?? '';
        $comment->save();

        $this->report->increment('note_comments', $comment->wasRecentlyCreated ? 'created' : 'updated');
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=NotesImporterTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/NotesImporter.php backend/tests/Feature/FirestoreImport/NotesImporterTest.php
git commit -m "feat: add NotesImporter mapping Firestore notes to community_posts"
```

---

### Task 13: `WellnessImporter` (fasting doc + history)

**Files:**
- Create: `backend/app/Services/FirestoreImport/WellnessImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/WellnessImporterTest.php`

**Interfaces:**
- Produces: `WellnessImporter::import(bool $dryRun): void`.
- Consumes: `SnapshotReader::collectionGroup('wellness')` (path `users/{uid}/wellness/fasting`), `SnapshotReader::collectionGroup('history')` (path `users/{uid}/wellness/fasting/history/{id}`).

**Note for whoever runs this migration:** `fasting_timer_screen.dart` and `watch_steps_receiver.dart` write to this Firestore path *live*, right now — this is the one collection in the whole migration that wasn't already cut over to the API. Migrating its historical data (this task) does not stop the current app from continuing to write new fasting sessions to Firestore after cutover. That's a real gap for a follow-up task (porting the fasting timer feature to the API), separate from — and out of scope for — this data-transfer plan.

- [ ] **Step 1: Write a failing test**

```php
<?php
// backend/tests/Feature/FirestoreImport/WellnessImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\FastingHistory;
use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\WellnessImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class WellnessImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/wellness-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_the_fasting_doc_onto_the_user_and_history_entries_into_fasting_history(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/_group_wellness.json", json_encode([
            ['id' => 'fasting', 'path' => 'users/uid-1/wellness/fasting', 'data' => [
                'targetHours' => 16, 'startTime' => '2025-04-01T08:00:00.000Z',
                'endTime' => null, 'lastCompletedAt' => '2025-03-30T08:00:00.000Z',
            ]],
        ]));
        File::put("{$this->dir}/_group_history.json", json_encode([
            ['id' => 'hist-1', 'path' => 'users/uid-1/wellness/fasting/history/hist-1', 'data' => [
                'targetHours' => 16, 'startTime' => '2025-03-29T08:00:00.000Z', 'plannedEndTime' => '2025-03-30T00:00:00.000Z',
                'finishedAt' => '2025-03-30T08:00:00.000Z', 'completedHours' => 24.0, 'completedTarget' => true,
                'createdAt' => '2025-03-30T08:00:00.000Z',
            ]],
        ]));

        $importer = new WellnessImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user->refresh();
        $this->assertSame(16, $user->fasting_target_hours);
        $this->assertNotNull($user->fasting_start_at);
        $this->assertNull($user->fasting_end_at);
        $this->assertNotNull($user->fasting_last_completed_at);

        $entry = FastingHistory::where('firestore_id', 'hist-1')->first();
        $this->assertNotNull($entry);
        $this->assertSame($user->id, $entry->user_id);
        $this->assertSame(16, $entry->target_hours);
        $this->assertTrue((bool) $entry->completed_target);
        $this->assertEqualsWithDelta(24.0, (float) $entry->completed_hours, 0.001);
    }

    public function test_skips_history_entries_with_no_matching_user(): void
    {
        File::put("{$this->dir}/_group_wellness.json", json_encode([]));
        File::put("{$this->dir}/_group_history.json", json_encode([
            ['id' => 'hist-1', 'path' => 'users/missing-uid/wellness/fasting/history/hist-1', 'data' => ['targetHours' => 16]],
        ]));

        $report = new ImportReport();
        $importer = new WellnessImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, FastingHistory::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=WellnessImporterTest`
Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement `WellnessImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/WellnessImporter.php

namespace App\Services\FirestoreImport;

use App\Models\FastingHistory;
use App\Models\User;
use Illuminate\Support\Carbon;

class WellnessImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collectionGroup('wellness') as $record) {
            $this->importFastingDoc($record);
        }
        foreach ($this->reader->collectionGroup('history') as $record) {
            $this->importFastingHistoryEntry($record);
        }
    }

    private function importFastingDoc(array $record): void
    {
        $uid = explode('/', $record['path'])[1] ?? null;
        $user = $uid !== null ? User::where('firebase_uid', $uid)->first() : null;
        if ($user === null) {
            $this->report->skip('users.fasting', $record['id'], "no matching user for uid {$uid}");

            return;
        }

        $data = $record['data'];
        $user->fasting_target_hours = $data['targetHours'] ?? $user->fasting_target_hours;
        $user->fasting_start_at = $data['startTime'] ?? null;
        $user->fasting_end_at = $data['endTime'] ?? null;
        $user->fasting_last_completed_at = $data['lastCompletedAt'] ?? $user->fasting_last_completed_at;
        $user->save();

        $this->report->increment('users.fasting', 'updated');
    }

    private function importFastingHistoryEntry(array $record): void
    {
        $uid = explode('/', $record['path'])[1] ?? null;
        $userId = $uid !== null ? User::where('firebase_uid', $uid)->value('id') : null;
        if ($userId === null) {
            $this->report->skip('fasting_history', $record['id'], "no matching user for uid {$uid}");

            return;
        }

        $data = $record['data'];
        $entry = FastingHistory::where('firestore_id', $record['id'])->first() ?? new FastingHistory();
        $entry->firestore_id = $record['id'];
        $entry->user_id = $userId;
        $entry->target_hours = $data['targetHours'] ?? 0;
        $entry->start_time = $data['startTime'] ?? null;
        $entry->planned_end_time = $data['plannedEndTime'] ?? null;
        $entry->finished_at = $data['finishedAt'] ?? null;
        $entry->completed_hours = $data['completedHours'] ?? 0;
        $entry->completed_target = $data['completedTarget'] ?? false;

        if (! empty($data['createdAt'])) {
            $entry->timestamps = false;
            $entry->created_at = Carbon::parse($data['createdAt']);
            $entry->updated_at = $entry->created_at;
        }

        $entry->save();

        $this->report->increment('fasting_history', $entry->wasRecentlyCreated ? 'created' : 'updated');
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=WellnessImporterTest`
Expected: PASS, both tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/FirestoreImport/WellnessImporter.php backend/tests/Feature/FirestoreImport/WellnessImporterTest.php
git commit -m "feat: add WellnessImporter for fasting profile fields and history"
```

---

### Task 14: `UserPointsImporter` (data-driven — requires real-snapshot inspection)

**Files:**
- Create: `backend/app/Services/FirestoreImport/UserPointsImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/UserPointsImporterTest.php`

**Interfaces:**
- Produces: `UserPointsImporter::import(bool $dryRun): void`.
- Consumes: `SnapshotReader::collection('userpoints')`.

Unlike every other collection in this plan, no Dart code in the current app reads fields back out of Firestore `userpoints` docs — the only live interaction is a blind `username` rewrite on account rename (`edit_profile.dart:222-233`). That means the field names below are **not confirmed against real data**, only inferred from the *current* Postgres `user_points` schema and the *current* API's `UserPointApiService.upsert()` payload shape, on the hypothesis that the historical Firestore schema was similar before the API cutover. Step 1 requires inspecting a real exported file before finalizing the mapper — do not skip it.

- [ ] **Step 1: Inspect real exported data (required before trusting the field mapping below)**

Run: `cat scripts/firestore-export/snapshot/userpoints.json | head -c 2000` (using the real snapshot produced by Task 1 once it's been run against production).

Compare the actual field names present against the hypothesis this task assumes: `date`, `username`, `totalPoints`, `activityPoints`, `dailyTrackerScore`, `todoListScore`, `todoListScoreDailyContribution`, `todoListIncludedInTotal`, `userTotalScore`, `taskPoints`, `tasks`, `server`, `companyId`, `companyCode`, `companyName`, `activityCounts`. **If the real field names differ, update Step 3's mapper (and Step 2's test fixture) to match reality before proceeding** — this is the one place in the whole plan where the code below is a starting hypothesis, not a verified fact.

- [ ] **Step 2: Write a failing test using the hypothesized field shape**

```php
<?php
// backend/tests/Feature/FirestoreImport/UserPointsImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\User;
use App\Models\UserPoint;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\UserPointsImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class UserPointsImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/userpoints-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_daily_points_record_for_a_matching_user(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'uid-1_2025-04-01', 'data' => [
                'userId' => 'uid-1', 'date' => '2025-04-01', 'username' => 'Jane',
                'totalPoints' => 12.5, 'activityPoints' => 5, 'dailyTrackerScore' => 4,
                'todoListScore' => 3, 'todoListScoreDailyContribution' => 1,
                'todoListIncludedInTotal' => true, 'userTotalScore' => 100,
                'server' => 'main', 'companyId' => 'co-1', 'companyCode' => 'ABC', 'companyName' => 'Acme',
            ]],
        ]));

        $importer = new UserPointsImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = UserPoint::where('user_id', $user->id)->where('date', '2025-04-01')->first();
        $this->assertNotNull($record);
        $this->assertSame('Jane', $record->username);
        $this->assertEqualsWithDelta(12.5, (float) $record->total_points, 0.001);
        $this->assertSame(4, $record->daily_tracker_score);
        $this->assertTrue((bool) $record->todo_list_included_in_total);
    }

    public function test_skips_a_record_with_no_matching_user(): void
    {
        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'x', 'data' => ['userId' => 'missing-uid', 'date' => '2025-04-01']],
        ]));

        $report = new ImportReport();
        $importer = new UserPointsImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, UserPoint::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=UserPointsImporterTest`
Expected: FAIL — class doesn't exist.

- [ ] **Step 4: Implement `UserPointsImporter`**

```php
<?php
// backend/app/Services/FirestoreImport/UserPointsImporter.php

namespace App\Services\FirestoreImport;

use App\Models\User;
use App\Models\UserPoint;

class UserPointsImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('userpoints') as $record) {
            $this->importRecord($record['id'], $record['data']);
        }
    }

    private function importRecord(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        $date = $data['date'] ?? null;
        if ($userId === null || $date === null) {
            $this->report->skip('user_points', $firestoreId, 'missing matching user or date');

            return;
        }

        $record = UserPoint::where('user_id', $userId)->where('date', $date)->first() ?? new UserPoint();
        $record->user_id = $userId;
        $record->date = $date;
        $record->username = $data['username'] ?? '';
        $record->total_points = $data['totalPoints'] ?? 0;
        $record->activity_points = $data['activityPoints'] ?? 0;
        $record->daily_tracker_score = $data['dailyTrackerScore'] ?? 0;
        $record->todo_list_score = $data['todoListScore'] ?? 0;
        $record->todo_list_score_daily_contribution = $data['todoListScoreDailyContribution'] ?? 0;
        $record->todo_list_included_in_total = $data['todoListIncludedInTotal'] ?? false;
        $record->user_total_score = $data['userTotalScore'] ?? 0;
        $record->task_points = $data['taskPoints'] ?? null;
        $record->tasks = $data['tasks'] ?? null;
        $record->server = $data['server'] ?? null;
        $record->company_id = $data['companyId'] ?? null;
        $record->company_code = $data['companyCode'] ?? null;
        $record->company_name = $data['companyName'] ?? null;
        $record->activity_counts = $data['activityCounts'] ?? null;
        $record->save();

        $this->report->increment('user_points', $record->wasRecentlyCreated ? 'created' : 'updated');
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=UserPointsImporterTest`
Expected: PASS, both tests green.

- [ ] **Step 6: Commit**

```bash
git add backend/app/Services/FirestoreImport/UserPointsImporter.php backend/tests/Feature/FirestoreImport/UserPointsImporterTest.php
git commit -m "feat: add UserPointsImporter (field mapping pending real-snapshot confirmation)"
```

---

### Task 15: Wire all importers into the command + rollout checklist

**Files:**
- Modify: `backend/app/Console/Commands/ImportFirestoreData.php:53-56` (the `importers()` method from Task 8)
- Test: `backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php`

**Interfaces:**
- Consumes: every Importer class from Tasks 9–14.

Order matters: `users` must run before everything else (every other importer resolves foreign keys via `firebase_uid`); `goals` must run before nothing else in this list depends on it, but nothing else produces goal data either, so its position relative to `notes`/`wellness`/`userpoints` doesn't matter. `coach_mentees` synthesis depends on `users` only, not on `goals`.

- [ ] **Step 1: Write a failing end-to-end test combining two importers**

```php
// Add to backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php

use App\Models\Goal;
use App\Models\User;
use Illuminate\Support\Facades\File;

    public function test_full_run_imports_a_user_and_their_goal_in_dependency_order(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-e2e-'.uniqid();
        File::ensureDirectoryExists($dir);

        File::put("$dir/users.json", json_encode([['id' => 'uid-1', 'data' => ['username' => 'Jane']]]));
        File::put("$dir/coaches.json", json_encode([]));
        File::put("$dir/coach_groups.json", json_encode([]));
        File::put("$dir/coach_requests.json", json_encode([]));
        File::put("$dir/notes.json", json_encode([]));
        File::put("$dir/userpoints.json", json_encode([]));
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-1', 'email' => 'jane@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));
        File::put("$dir/goals.json", json_encode([
            ['id' => 'goal-1', 'data' => ['userId' => 'uid-1', 'title' => 'Read 12 books', 'category' => 'PERSONAL', 'status' => 'IN_PROGRESS', 'goalType' => 'MILESTONE', 'direction' => 'GAIN', 'targetPeriod' => 'NONE', 'startDate' => '2025-01-01', 'targetDate' => '2025-12-31']],
        ]));
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }

        $this->artisan('firestore:import', ['--path' => $dir])
            ->assertExitCode(0);

        $user = User::where('firebase_uid', 'uid-1')->first();
        $this->assertNotNull($user);
        $this->assertSame(1, Goal::where('user_id', $user->id)->count());

        File::deleteDirectory($dir);
    }

    public function test_dry_run_does_not_persist_any_changes(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-dryrun-'.uniqid();
        File::ensureDirectoryExists($dir);
        File::put("$dir/users.json", json_encode([['id' => 'uid-9', 'data' => ['username' => 'DryRun']]]));
        foreach (['coaches', 'coach_groups', 'coach_requests', 'notes', 'userpoints', 'goals'] as $name) {
            File::put("$dir/{$name}.json", json_encode([]));
        }
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-9', 'email' => 'dryrun@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $this->artisan('firestore:import', ['--path' => $dir, '--dry-run' => true])
            ->assertExitCode(0);

        $this->assertSame(0, User::where('firebase_uid', 'uid-9')->count());

        File::deleteDirectory($dir);
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && php artisan test --filter=ImportFirestoreDataCommandTest`
Expected: FAIL — `importers()` still returns an empty array, so no `User`/`Goal` rows get created.

- [ ] **Step 3: Wire the real importers into the command**

Replace the `importers()` method in `backend/app/Console/Commands/ImportFirestoreData.php`:

```php
use App\Services\FirestoreImport\CoachRelationshipImporter;
use App\Services\FirestoreImport\GoalImporter;
use App\Services\FirestoreImport\NotesImporter;
use App\Services\FirestoreImport\UserImporter;
use App\Services\FirestoreImport\UserPointsImporter;
use App\Services\FirestoreImport\WellnessImporter;

    private function importers(SnapshotReader $reader, ImportReport $report): array
    {
        return [
            new UserImporter($reader, $report),
            new CoachRelationshipImporter($reader, $report),
            new GoalImporter($reader, $report),
            new NotesImporter($reader, $report),
            new WellnessImporter($reader, $report),
            new UserPointsImporter($reader, $report),
        ];
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && php artisan test --filter=ImportFirestoreDataCommandTest`
Expected: PASS, all 4 tests (2 from Task 8, 2 new ones) green.

- [ ] **Step 5: Run the full backend test suite**

Run: `cd backend && php artisan test`
Expected: PASS — every pre-existing test (AuthTest, CoachManagementTest, etc.) still passes alongside every new FirestoreImport test.

- [ ] **Step 6: Commit**

```bash
git add backend/app/Console/Commands/ImportFirestoreData.php backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php
git commit -m "feat: wire all Firestore importers into firestore:import in dependency order"
```

- [ ] **Step 7: Manual production rollout checklist (not automatable — requires real Firebase/production access)**

1. Run `scripts/firestore-export/export-firestore.js` and `export-auth.sh` against production Firestore (`selfcare-1476e`), producing a real `snapshot/` directory.
2. Copy that `snapshot/` directory to `backend/storage/app/firestore-snapshot/` (or point `--path` at wherever it lives).
3. `npm install` inside `backend/scripts/firebase-auth-verify/` on whatever host will run production `AuthController::login()` — the verifier subprocess needs its `node_modules` present.
4. Re-run Task 4 Step 5's manual match/no-match check against the real production `hash-config.json` — confirm before trusting logins.
5. `cd backend && php artisan firestore:import --dry-run` against the real snapshot; read the printed summary; investigate every `SKIPPED` line before proceeding.
6. `cd backend && php artisan firestore:import` for real (no `--dry-run`), before releasing the new app version.
7. Spot-check a handful of migrated accounts by hand: confirm login works for at least one real password-based account (proves the whole chain end-to-end, not just the isolated Task 4 Step 5 check), and that their goals/points/notes/fasting-history show up correctly against what's in the original Firestore console.
8. Only after that spot-check passes, release the new Laravel-backed app version.
