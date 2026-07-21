<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->unsignedInteger('meditation_streak_current')->nullable()->after('daily_step_goal');
            $table->unsignedInteger('meditation_streak_longest')->nullable()->after('meditation_streak_current');
            $table->string('meditation_streak_last_date')->nullable()->after('meditation_streak_longest');
            $table->json('meditation_streak_rewards')->nullable()->after('meditation_streak_last_date');

            $table->unsignedInteger('steps_streak_current')->nullable()->after('meditation_streak_rewards');
            $table->unsignedInteger('steps_streak_longest')->nullable()->after('steps_streak_current');
            $table->string('steps_streak_last_date')->nullable()->after('steps_streak_longest');
            $table->json('steps_streak_rewards')->nullable()->after('steps_streak_last_date');

            $table->unsignedInteger('exercise_streak_current')->nullable()->after('steps_streak_rewards');
            $table->unsignedInteger('exercise_streak_longest')->nullable()->after('exercise_streak_current');
            $table->string('exercise_streak_last_date')->nullable()->after('exercise_streak_longest');
            $table->json('exercise_streak_rewards')->nullable()->after('exercise_streak_last_date');

            $table->unsignedInteger('fasting_streak_current')->nullable()->after('exercise_streak_rewards');
            $table->unsignedInteger('fasting_streak_longest')->nullable()->after('fasting_streak_current');
            $table->string('fasting_streak_last_date')->nullable()->after('fasting_streak_longest');
            $table->json('fasting_streak_rewards')->nullable()->after('fasting_streak_last_date');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn([
                'meditation_streak_current',
                'meditation_streak_longest',
                'meditation_streak_last_date',
                'meditation_streak_rewards',
                'steps_streak_current',
                'steps_streak_longest',
                'steps_streak_last_date',
                'steps_streak_rewards',
                'exercise_streak_current',
                'exercise_streak_longest',
                'exercise_streak_last_date',
                'exercise_streak_rewards',
                'fasting_streak_current',
                'fasting_streak_longest',
                'fasting_streak_last_date',
                'fasting_streak_rewards',
            ]);
        });
    }
};
