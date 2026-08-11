<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Supports the bounded newest-first heart popover without sorting a
        // popular post's complete reaction history in application memory.
        Schema::table('community_post_hearts', function (Blueprint $table): void {
            $table->index(
                ['community_post_id', 'created_at'],
                'community_post_hearts_post_created_index',
            );
        });
    }

    public function down(): void
    {
        Schema::table('community_post_hearts', function (Blueprint $table): void {
            $table->dropIndex('community_post_hearts_post_created_index');
        });
    }
};
