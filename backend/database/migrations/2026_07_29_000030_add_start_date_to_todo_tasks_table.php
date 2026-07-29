<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('todo_tasks', function (Blueprint $table): void {
            $table->date('start_date')->nullable()->after('description');
            $table->index(['user_id', 'start_date']);
        });
    }

    public function down(): void
    {
        Schema::table('todo_tasks', function (Blueprint $table): void {
            $table->dropIndex(['user_id', 'start_date']);
            $table->dropColumn('start_date');
        });
    }
};
