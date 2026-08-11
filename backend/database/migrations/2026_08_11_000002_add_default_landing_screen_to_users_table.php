<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            // Store a semantic destination, not a client tab index. Different
            // company shells have different tab arrangements, and the client
            // can safely fall back to Dashboard when a destination is absent.
            $table->string('default_landing_screen', 32)
                ->default('dashboard')
                ->after('daily_step_goal');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn('default_landing_screen');
        });
    }
};
