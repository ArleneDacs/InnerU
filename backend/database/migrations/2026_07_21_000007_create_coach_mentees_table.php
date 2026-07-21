<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('coach_mentees', function (Blueprint $table): void {
            $table->id();
            $table->string('coach_id');
            $table->string('mentee_id');
            $table->string('mentee_name')->nullable();
            $table->string('mentee_email')->nullable();
            $table->string('team_name')->nullable();
            $table->string('group_id')->nullable();
            $table->string('group_name')->nullable();
            $table->timestamps();

            $table->unique(['coach_id', 'mentee_id']);
            $table->index(['coach_id', 'group_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('coach_mentees');
    }
};
