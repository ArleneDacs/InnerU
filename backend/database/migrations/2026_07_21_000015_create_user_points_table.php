<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_points', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->date('date');
            $table->string('username');
            $table->decimal('total_points', 8, 2)->default(0);
            $table->integer('activity_points')->default(0);
            $table->integer('daily_tracker_score')->default(0);
            $table->integer('todo_list_score')->default(0);
            $table->integer('todo_list_score_daily_contribution')->default(0);
            $table->boolean('todo_list_included_in_total')->default(false);
            $table->integer('user_total_score')->default(0);
            $table->json('task_points')->nullable();
            $table->json('tasks')->nullable();
            $table->string('server')->nullable();
            $table->string('company_id')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->json('activity_counts')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'date', 'company_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_points');
    }
};
