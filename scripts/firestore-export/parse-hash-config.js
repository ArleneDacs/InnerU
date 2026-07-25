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
