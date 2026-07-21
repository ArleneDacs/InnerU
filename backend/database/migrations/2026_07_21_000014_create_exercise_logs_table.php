<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('exercise_logs', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('username');
            $table->string('type');
            $table->unsignedInteger('duration_minutes');
            $table->unsignedTinyInteger('intensity')->default(2);
            $table->text('notes')->nullable();
            $table->string('start_photo_url')->nullable();
            $table->string('end_photo_url')->nullable();
            $table->date('date');
            $table->timestamps();
            $table->index(['user_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('exercise_logs');
    }
};
