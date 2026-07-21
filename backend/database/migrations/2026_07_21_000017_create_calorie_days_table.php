<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('calorie_days', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->date('date');
            $table->unsignedInteger('daily_goal')->default(2000);
            $table->unsignedInteger('total_calories')->default(0);
            $table->unsignedInteger('total_protein')->default(0);
            $table->unsignedInteger('total_carbs')->default(0);
            $table->unsignedInteger('total_fat')->default(0);
            $table->unsignedInteger('meal_count')->default(0);
            $table->unsignedInteger('water_glasses')->default(0);
            $table->unsignedInteger('water_goal')->default(8);
            $table->timestamps();
            $table->unique(['user_id', 'date']);
            $table->index(['user_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('calorie_days');
    }
};
