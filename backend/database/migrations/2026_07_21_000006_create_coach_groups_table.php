<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('coach_groups', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('coach_id');
            $table->string('name');
            $table->json('member_ids')->nullable();
            $table->unsignedInteger('member_count')->default(0);
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamps();

            $table->index(['coach_id', 'company_code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coach_groups');
    }
};
