<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('community_posts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('username');
            $table->string('title');
            $table->json('note');
            $table->unsignedInteger('color')->default(0xFFFFFFFF);
            $table->string('category');
            $table->boolean('saved')->default(false);
            $table->string('company_id')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('community_posts');
    }
};
