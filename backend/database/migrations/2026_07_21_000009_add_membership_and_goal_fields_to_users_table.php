<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->boolean('has_company')->default(false)->after('profile_pic');
            $table->string('company_id')->nullable()->after('has_company');
            $table->string('active_company_id')->nullable()->after('company_id');
            $table->string('active_company_code')->nullable()->after('active_company_id');
            $table->string('active_company_name')->nullable()->after('active_company_code');
            $table->string('active_company_score_mode')->nullable()->after('active_company_name');
            $table->string('score_mode')->nullable()->after('active_company_score_mode');
            $table->json('company_memberships')->nullable()->after('score_mode');
            $table->json('company_ids')->nullable()->after('company_memberships');
            $table->json('company_codes')->nullable()->after('company_ids');
            $table->unsignedInteger('daily_step_goal')->nullable()->after('company_codes');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn([
                'has_company',
                'company_id',
                'active_company_id',
                'active_company_code',
                'active_company_name',
                'active_company_score_mode',
                'score_mode',
                'company_memberships',
                'company_ids',
                'company_codes',
                'daily_step_goal',
            ]);
        });
    }
};
