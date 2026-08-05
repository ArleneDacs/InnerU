<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->json('mentions')->nullable()->after('note');
        });
        Schema::table('note_comments', function (Blueprint $table) {
            $table->json('mentions')->nullable()->after('comment');
        });
    }

    public function down(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->dropColumn('mentions');
        });
        Schema::table('note_comments', function (Blueprint $table) {
            $table->dropColumn('mentions');
        });
    }
};
