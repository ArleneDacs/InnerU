<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('food_memories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('key');
            $table->string('display_name');
            $table->string('lookup_name');
            $table->unsignedInteger('calories');
            $table->unsignedInteger('protein')->default(0);
            $table->unsignedInteger('carbs')->default(0);
            $table->unsignedInteger('fat')->default(0);
            $table->string('source')->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('food_memories');
    }
};
