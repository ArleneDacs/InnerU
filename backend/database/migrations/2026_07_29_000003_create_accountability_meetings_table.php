<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('accountability_meetings', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('coach_id');
            $table->string('group_id');
            $table->string('title');
            $table->string('zoom_link');
            $table->string('notes')->nullable();
            $table->timestamp('scheduled_at');
            $table->timestamp('day_before_notified_at')->nullable();
            $table->timestamp('day_of_notified_at')->nullable();
            $table->timestamps();

            $table->index('group_id');
            $table->index('scheduled_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('accountability_meetings');
    }
};
