<?php

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
