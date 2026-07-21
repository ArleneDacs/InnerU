<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fasting_history', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->unsignedInteger('target_hours');
            $table->timestamp('start_time')->nullable();
            $table->timestamp('planned_end_time')->nullable();
            $table->timestamp('finished_at');
            $table->decimal('completed_hours', 6, 2);
            $table->boolean('completed_target')->default(false);
            $table->timestamps();
            $table->index(['user_id', 'finished_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fasting_history');
    }
};
