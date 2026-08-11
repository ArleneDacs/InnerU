<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('app_versions', function (Blueprint $table): void {
            // Default to the historical behavior: an older client must update
            // unless an administrator explicitly marks a release optional.
            $table->boolean('ios_update_required')->default(true);
            $table->boolean('android_update_required')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('app_versions', function (Blueprint $table): void {
            $table->dropColumn([
                'ios_update_required',
                'android_update_required',
            ]);
        });
    }
};
