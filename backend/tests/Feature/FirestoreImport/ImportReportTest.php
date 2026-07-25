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
