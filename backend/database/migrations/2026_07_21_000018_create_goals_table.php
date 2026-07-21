<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goals', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('company_id')->nullable();
            $table->string('category');
            $table->string('title');
            $table->text('description')->nullable();
            $table->text('notes')->nullable();
            $table->string('status');
            $table->string('goal_type');
            $table->string('direction');
            $table->decimal('target_value', 12, 2)->default(0);
            $table->decimal('current_value', 12, 2)->default(0);
            $table->string('unit')->nullable();
            $table->string('target_period');
            $table->date('start_date');
            $table->date('target_date');
            $table->timestamp('completed_at')->nullable();
            $table->unsignedSmallInteger('progress')->default(0);
            $table->timestamps();

            $table->index(['user_id', 'target_date']);
            $table->index(['user_id', 'status']);
            $table->index(['user_id', 'category']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goals');
    }
};
