<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goal_tasks', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('goal_id');
            $table->string('title');
            $table->string('status');
            $table->boolean('is_complete')->default(false);
            $table->timestamp('due_date')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->unsignedTinyInteger('weight')->default(1);
            $table->timestamps();

            $table->foreign('goal_id')->references('id')->on('goals')->cascadeOnDelete();
            $table->index(['goal_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goal_tasks');
    }
};
