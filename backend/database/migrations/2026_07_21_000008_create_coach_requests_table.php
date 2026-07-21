<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('coach_requests', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('coach_id');
            $table->string('coach_name')->nullable();
            $table->string('coach_email')->nullable();
            $table->string('mentee_id');
            $table->string('mentee_name')->nullable();
            $table->string('mentee_email')->nullable();
            $table->string('applicant_role')->nullable();
            $table->boolean('applicant_is_coach')->default(false);
            $table->string('applying_as')->default('mentee');
            $table->string('status')->default('pending');
            $table->string('group_id')->nullable();
            $table->string('group_name')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamp('accepted_at')->nullable();
            $table->timestamps();

            $table->index(['coach_id', 'status']);
            $table->index(['mentee_id', 'coach_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coach_requests');
    }
};
