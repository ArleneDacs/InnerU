<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('companies', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('name');
            $table->string('code')->unique();
            $table->boolean('is_active')->default(true);
            $table->boolean('theme_enabled')->default(false);
            $table->string('theme_source')->nullable();
            $table->string('tagline')->nullable();
            $table->string('theme_primary_color')->nullable();
            $table->string('theme_accent_color')->nullable();
            $table->string('theme_background_color')->nullable();
            $table->string('theme_surface_color')->nullable();
            $table->string('theme_ink_color')->nullable();
            $table->string('theme_muted_ink_color')->nullable();
            $table->string('theme_icon_color')->nullable();
            $table->string('theme_mode')->nullable();
            $table->boolean('theme_is_dark')->default(false);
            $table->string('logo_url')->nullable();
            $table->string('logo_file_name')->nullable();
            $table->timestamp('logo_updated_at')->nullable();
            $table->string('loading_image_url')->nullable();
            $table->string('loading_image_file_name')->nullable();
            $table->timestamp('loading_image_updated_at')->nullable();
            $table->string('loading_video_url')->nullable();
            $table->string('loading_video_file_name')->nullable();
            $table->timestamp('loading_video_updated_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('companies');
    }
};
