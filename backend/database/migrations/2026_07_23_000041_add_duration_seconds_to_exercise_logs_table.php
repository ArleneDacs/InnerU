<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('exercise_logs', function (Blueprint $table): void {
            $table->unsignedInteger('duration_seconds')->nullable()->after('duration_minutes');
        });
    }

    public function down(): void
    {
        Schema::table('exercise_logs', function (Blueprint $table): void {
            $table->dropColumn('duration_seconds');
        });
    }
};
