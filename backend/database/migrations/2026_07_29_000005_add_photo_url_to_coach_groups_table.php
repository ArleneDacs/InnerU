<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('coach_groups', function (Blueprint $table): void {
            $table->string('photo_url')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('coach_groups', function (Blueprint $table): void {
            $table->dropColumn('photo_url');
        });
    }
};
