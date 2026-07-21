<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goal_comments', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('goal_id');
            $table->foreignId('author_id')->constrained('users')->cascadeOnDelete();
            $table->text('body');
            $table->boolean('is_private')->default(false);
            $table->timestamps();

            $table->foreign('goal_id')->references('id')->on('goals')->cascadeOnDelete();
            $table->index(['goal_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goal_comments');
    }
};
