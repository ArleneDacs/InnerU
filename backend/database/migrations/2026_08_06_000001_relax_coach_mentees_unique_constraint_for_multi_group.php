<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A coach used to get exactly one `coach_mentees` row per mentee (unique
     * on coach_id+mentee_id), so a mentee could only ever be "in" one of
     * that coach's groups at a time -- assigning them to a second group
     * silently moved them out of the first. This relaxes the constraint so
     * a coach can have one row per (coach, mentee, group) combination,
     * letting a mentee belong to several of the same coach's groups at
     * once. Existing rows are untouched: a row with a real group_id simply
     * becomes one membership among possibly several, and a row with a null
     * group_id ("main coach team", no specific group) keeps working as
     * before.
     *
     * Postgres/SQLite both treat NULL as distinct from NULL in a unique
     * index, so (coach_id, mentee_id, group_id) alone would let a mentee
     * accumulate multiple *null*-group rows for the same coach without
     * violating anything. The partial unique index below closes that gap
     * by keeping "no group" unique per (coach_id, mentee_id) even though
     * "with a group" is now allowed to repeat per group. Both SQLite (3.8+)
     * and Postgres support this exact partial-index syntax, so one
     * statement covers both test drivers (see phpunit.xml vs
     * phpunit.pgsql.xml).
     */
    public function up(): void
    {
        Schema::table('coach_mentees', function (Blueprint $table): void {
            $table->dropUnique(['coach_id', 'mentee_id']);
            $table->unique(['coach_id', 'mentee_id', 'group_id']);
        });

        DB::statement(
            'CREATE UNIQUE INDEX coach_mentees_coach_mentee_null_group_unique '.
            'ON coach_mentees (coach_id, mentee_id) WHERE group_id IS NULL'
        );
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS coach_mentees_coach_mentee_null_group_unique');

        Schema::table('coach_mentees', function (Blueprint $table): void {
            $table->dropUnique(['coach_id', 'mentee_id', 'group_id']);
            $table->unique(['coach_id', 'mentee_id']);
        });
    }
};
