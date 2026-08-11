<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('daily_trackers', function (Blueprint $table) {
            // Unlike updated_at, this is intentionally immutable once a
            // person finishes all of today's required Daily Tracker tasks.
            $table->timestamp('leaderboard_completed_at')->nullable()->index();
        });
    }

    public function down(): void
    {
        Schema::table('daily_trackers', function (Blueprint $table) {
            $table->dropIndex(['leaderboard_completed_at']);
            $table->dropColumn('leaderboard_completed_at');
        });
    }
};
