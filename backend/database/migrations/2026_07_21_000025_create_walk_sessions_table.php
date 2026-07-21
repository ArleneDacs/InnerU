<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('walk_sessions', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('created_by')->nullable();
            $table->string('created_by_name')->nullable();
            $table->string('status')->default('pending');
            $table->json('participant_ids')->nullable();
            $table->string('company_id')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamps();

            $table->index(['created_by', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('walk_sessions');
    }
};
