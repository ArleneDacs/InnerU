<?php

use App\Models\Company;
use App\Services\CompanyUserTableService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table): void {
            $table->string('user_table_name', 68)->nullable()->unique()->after('code');
        });

        app(CompanyUserTableService::class)->backfillAll();
    }

    public function down(): void
    {
        foreach (Company::query()->whereNotNull('user_table_name')->get() as $company) {
            app(CompanyUserTableService::class)->dropFor($company);
        }

        Schema::table('companies', function (Blueprint $table): void {
            $table->dropColumn('user_table_name');
        });
    }
};
