<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('meeting_attendances', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('meeting_id');
            $table->string('mentee_id');
            $table->timestamp('joined_at');
            $table->timestamps();

            $table->unique(['meeting_id', 'mentee_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('meeting_attendances');
    }
};
