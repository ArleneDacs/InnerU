<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goal_merits', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('goal_id');
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->date('date');
            $table->decimal('amount', 12, 2)->default(0);
            $table->timestamps();

            $table->foreign('goal_id')->references('id')->on('goals')->cascadeOnDelete();
            $table->index(['goal_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goal_merits');
    }
};
