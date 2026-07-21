<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recorded_walks', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('username')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->unsignedInteger('step_count')->default(0);
            $table->decimal('distance_meters', 12, 2)->default(0);
            $table->unsignedInteger('elapsed_seconds')->default(0);
            $table->json('route_points')->nullable();
            $table->boolean('interrupted')->default(false);
            $table->timestamps();

            $table->index(['user_id', 'ended_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recorded_walks');
    }
};
