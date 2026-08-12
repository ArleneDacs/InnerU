<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->string('client_submission_id', 100)->nullable()->after('firestore_id');
            $table->unique(['user_id', 'client_submission_id']);
        });
    }

    public function down(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'client_submission_id']);
            $table->dropColumn('client_submission_id');
        });
    }
};
