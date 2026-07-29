<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('step_submissions', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('user_id');
            $table->integer('steps');
            $table->date('date');
            $table->string('proof_url');
            $table->string('note')->nullable();
            $table->string('status')->default('pending');
            $table->string('decline_reason')->nullable();
            $table->string('reviewed_by')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'status']);
            $table->index(['status', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('step_submissions');
    }
};
