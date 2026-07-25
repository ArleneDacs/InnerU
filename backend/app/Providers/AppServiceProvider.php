<?php

namespace App\Providers;

use App\Services\FirebaseScryptVerifier;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Schema;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->singleton(FirebaseScryptVerifier::class, function () {
            return new FirebaseScryptVerifier(
                config('services.firebase_scrypt.node_verifier_path'),
                config('services.firebase_scrypt.hash_config_path'),
            );
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            return;
        }

        try {
            if (! Schema::hasTable('pending_registrations')) {
                Schema::create('pending_registrations', function (Blueprint $table): void {
                    $table->id();
                    $table->string('name');
                    $table->string('email')->unique();
                    $table->string('apple_user_id')->nullable()->unique();
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
        } catch (\Throwable) {
            // If the database is unavailable, let the request fail naturally.
        }
    }
}
