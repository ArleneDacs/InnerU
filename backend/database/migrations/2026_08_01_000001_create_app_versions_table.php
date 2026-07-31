<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_versions', function (Blueprint $table): void {
            $table->id();
            $table->string('ios_latest_version', 32);
            $table->string('ios_store_url')->nullable();
            $table->unsignedInteger('android_latest_version_code');
            $table->string('android_store_url')->nullable();
            $table->timestamps();
        });

        DB::table('app_versions')->insert([
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('app_versions');
    }
};
