<?php

namespace App\Services;

use App\Models\Company;
use Illuminate\Support\Facades\DB;

class CompanyUserTableService
{
    public function tableNameFor(string $code): string
    {
        return $this->sanitizeIdentifier($code).'_users';
    }

    public function createFor(Company $company): void
    {
        $tableName = $this->tableNameFor($company->code);

        if ($this->objectExists($tableName)) {
            throw new \RuntimeException(
                "Cannot create per-company table \"{$tableName}\" for company {$company->id}: a database object with that name already exists."
            );
        }

        if (! preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $company->id)) {
            throw new \RuntimeException("Company id \"{$company->id}\" is not a UUID; refusing to embed it in a view definition.");
        }

        DB::statement("CREATE VIEW {$tableName} AS SELECT * FROM company_user_directory WHERE company_id = '{$company->id}'");

        $company->forceFill(['user_table_name' => $tableName])->save();
    }

    public function dropFor(Company $company): void
    {
        $tableName = $company->user_table_name;

        if ($tableName === null || $tableName === '') {
            return;
        }

        if (! preg_match('/^[a-z_][a-z0-9_]*$/', $tableName)) {
            throw new \RuntimeException("Refusing to drop suspicious table name \"{$tableName}\".");
        }

        DB::statement("DROP VIEW IF EXISTS {$tableName}");
    }

    public function backfillAll(): void
    {
        Company::query()
            ->whereNull('user_table_name')
            ->chunkById(200, function ($companies): void {
                foreach ($companies as $company) {
                    $this->createFor($company);
                }
            });
    }

    private function sanitizeIdentifier(string $code): string
    {
        $slug = strtolower(trim($code));
        $slug = preg_replace('/[^a-z0-9]+/', '_', $slug);
        $slug = trim($slug, '_');

        if ($slug === '') {
            $slug = 'company';
        }

        if (preg_match('/^[0-9]/', $slug)) {
            $slug = 'c_'.$slug;
        }

        $slug = substr($slug, 0, 50);
        $slug = rtrim($slug, '_');

        if ($slug === '') {
            $slug = 'company';
        }

        return $slug;
    }

    private function objectExists(string $name): bool
    {
        $driver = DB::connection()->getDriverName();

        if ($driver === 'sqlite') {
            $result = DB::selectOne(
                "SELECT 1 AS found FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
                [$name]
            );

            return $result !== null;
        }

        $result = DB::selectOne(
            'SELECT 1 AS found FROM information_schema.tables WHERE table_name = ?',
            [$name]
        );

        return $result !== null;
    }
}
