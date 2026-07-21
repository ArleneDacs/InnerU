<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('daily_trackers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('username');
            $table->date('date');
            $table->unsignedInteger('step_count')->default(0);
            $table->unsignedInteger('step_goal')->default(5000);
            $table->boolean('meditation')->default(false);
            $table->boolean('steps')->default(false);
            $table->boolean('call')->default(false);
            $table->boolean('exercise')->default(false);
            $table->boolean('learning')->default(false);
            $table->boolean('add_value')->default(false);
            $table->boolean('todo_list')->default(false);
            $table->unsignedInteger('call_count')->default(0);
            $table->unsignedInteger('exercise_count')->default(0);
            $table->unsignedInteger('exercise_minutes')->default(0);
            $table->unsignedInteger('learning_count')->default(0);
            $table->unsignedInteger('value_count')->default(0);
            $table->unsignedInteger('todo_list_count')->default(0);
            $table->unsignedInteger('todo_list_score')->default(0);
            $table->unsignedInteger('todo_list_score_daily_contribution')->default(0);
            $table->boolean('todo_list_included_in_total')->default(false);
            $table->unsignedInteger('user_total_score')->default(0);
            $table->json('custom_daily_tasks')->nullable();
            $table->unsignedInteger('meditation_minutes')->default(0);
            $table->string('company_id')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('daily_trackers');
    }
};
