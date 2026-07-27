<?php

namespace App\Observers;

use App\Models\Company;
use App\Services\CompanyUserTableService;

class CompanyObserver
{
    public function __construct(private readonly CompanyUserTableService $companyUserTableService)
    {
    }

    public function created(Company $company): void
    {
        try {
            $this->companyUserTableService->createFor($company);
        } catch (\Throwable $e) {
            // createFor() throws before writing anything to the database in the
            // failure cases it detects (name collision, malformed id), but the
            // Company row itself was already committed by the time this
            // post-insert event fires — there is no surrounding transaction to
            // roll that back automatically (callers may create companies via
            // Company::create() directly, not only through a transactional
            // controller action). Delete the now-orphaned row ourselves so a
            // failed company creation never leaves a dangling record behind.
            try {
                $company->delete();
            } catch (\Throwable $cleanupException) {
                throw new \RuntimeException(
                    "Failed to clean up an orphaned company row after createFor() failed: {$cleanupException->getMessage()}",
                    previous: $e,
                );
            }

            throw $e;
        }
    }

    public function deleted(Company $company): void
    {
        $this->companyUserTableService->dropFor($company);
    }
}
