<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('calorie_entries', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('calorie_day_id')->constrained('calorie_days')->cascadeOnDelete();
            $table->date('date');
            $table->string('meal');
            $table->string('meal_type');
            $table->unsignedInteger('calories');
            $table->unsignedInteger('protein')->default(0);
            $table->unsignedInteger('carbs')->default(0);
            $table->unsignedInteger('fat')->default(0);
            $table->decimal('quantity', 10, 2)->nullable();
            $table->string('measurement_unit', 50)->nullable();
            $table->string('photo_url', 2048)->nullable();
            $table->timestamps();
            $table->index(['user_id', 'calorie_day_id']);
            $table->index(['user_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('calorie_entries');
    }
};
