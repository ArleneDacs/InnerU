<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('walk_session_members', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('walk_session_id');
            $table->string('user_id');
            $table->string('username')->nullable();
            $table->string('status')->default('accepted');
            $table->boolean('is_tracking')->default(false);
            $table->unsignedInteger('step_count')->default(0);
            $table->decimal('distance_meters', 12, 2)->default(0);
            $table->unsignedInteger('elapsed_seconds')->default(0);
            $table->json('route_points')->nullable();
            $table->decimal('current_location_lat', 10, 7)->nullable();
            $table->decimal('current_location_lng', 10, 7)->nullable();
            $table->timestamps();

            $table->foreign('walk_session_id')->references('id')->on('walk_sessions')->cascadeOnDelete();
            $table->index(['walk_session_id', 'user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('walk_session_members');
    }
};
