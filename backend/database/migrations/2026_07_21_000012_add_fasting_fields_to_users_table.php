<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->unsignedInteger('fasting_target_hours')->nullable()->after('fasting_streak_rewards');
            $table->timestamp('fasting_start_at')->nullable()->after('fasting_target_hours');
            $table->timestamp('fasting_end_at')->nullable()->after('fasting_start_at');
            $table->timestamp('fasting_last_completed_at')->nullable()->after('fasting_end_at');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn([
                'fasting_target_hours',
                'fasting_start_at',
                'fasting_end_at',
                'fasting_last_completed_at',
            ]);
        });
    }
};
