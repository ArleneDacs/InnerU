<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_messages', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('chat_room_id');
            $table->string('sender_id');
            $table->string('sender_name');
            $table->text('message')->nullable();
            $table->string('image_url')->nullable();
            $table->string('sender_profile_pic')->nullable();
            $table->timestamp('timestamp')->nullable();
            $table->timestamp('client_timestamp')->nullable();
            $table->timestamps();

            $table->foreign('chat_room_id')->references('id')->on('chat_rooms')->cascadeOnDelete();
            $table->index(['chat_room_id', 'client_timestamp']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_messages');
    }
};
