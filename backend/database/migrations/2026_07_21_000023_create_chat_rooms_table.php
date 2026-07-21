<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_rooms', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->boolean('is_group_chat')->default(false);
            $table->string('coach_id')->nullable();
            $table->string('coach_name')->nullable();
            $table->string('user_id')->nullable();
            $table->string('user_name')->nullable();
            $table->string('group_name')->nullable();
            $table->string('group_profile_pic')->nullable();
            $table->text('last_message')->nullable();
            $table->timestamp('last_message_time')->nullable();
            $table->string('last_sender_id')->nullable();
            $table->json('participants')->nullable();
            $table->json('participant_names')->nullable();
            $table->json('participant_profiles')->nullable();
            $table->json('unread_counts')->nullable();
            $table->json('last_read_at')->nullable();
            $table->string('company_id')->nullable();
            $table->string('company_code')->nullable();
            $table->string('company_name')->nullable();
            $table->timestamps();

            $table->index(['coach_id', 'user_id']);
            $table->index(['last_message_time']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_rooms');
    }
};
