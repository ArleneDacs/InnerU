<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('exercise_logs', function (Blueprint $table): void {
            // A locally generated ID survives offline retries. It is nullable
            // so existing/date-only clients continue to create logs normally.
            $table->string('client_session_id', 120)->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->unique(
                ['user_id', 'client_session_id'],
                'exercise_logs_user_client_session_unique',
            );
        });
    }

    public function down(): void
    {
        Schema::table('exercise_logs', function (Blueprint $table): void {
            $table->dropUnique('exercise_logs_user_client_session_unique');
            $table->dropColumn([
                'client_session_id',
                'started_at',
                'ended_at',
            ]);
        });
    }
};
