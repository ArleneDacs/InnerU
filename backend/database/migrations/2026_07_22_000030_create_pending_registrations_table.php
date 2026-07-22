<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('pending_registrations', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->text('encrypted_password');
            $table->string('number', 30)->nullable();
            $table->string('role', 30);
            $table->boolean('is_coach')->default(false);
            $table->string('company_code', 60)->nullable();
            $table->string('company_name', 120)->nullable();
            $table->boolean('has_company')->default(false);
            $table->string('company_id', 60)->nullable();
            $table->string('active_company_id', 60)->nullable();
            $table->string('active_company_code', 60)->nullable();
            $table->string('active_company_name', 120)->nullable();
            $table->string('active_company_score_mode', 30)->nullable();
            $table->string('score_mode', 30)->nullable();
            $table->json('company_memberships')->nullable();
            $table->json('company_ids')->nullable();
            $table->json('company_codes')->nullable();
            $table->unsignedInteger('daily_step_goal')->nullable();
            $table->json('daily_tracker_items')->nullable();
            $table->date('birthdate')->nullable();
            $table->string('profile_pic')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('pending_registrations');
    }
};
