<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('todo_tasks', function (Blueprint $table): void {
            $table->string('goal_type', 32)->default('LONG_TERM')->after('description');
            $table->json('completion_dates')->nullable()->after('completed_at');
        });
    }

    public function down(): void
    {
        Schema::table('todo_tasks', function (Blueprint $table): void {
            $table->dropColumn(['goal_type', 'completion_dates']);
        });
    }
};
