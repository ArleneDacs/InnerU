<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('walk_invites', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('walk_session_id');
            $table->string('from_user_id');
            $table->string('from_username')->nullable();
            $table->string('to_user_id');
            $table->string('to_username')->nullable();
            $table->string('status')->default('pending');
            $table->timestamps();

            $table->foreign('walk_session_id')->references('id')->on('walk_sessions')->cascadeOnDelete();
            $table->index(['to_user_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('walk_invites');
    }
};
