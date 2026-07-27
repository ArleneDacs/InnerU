<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // `latest.rn = 1` lives in the JOIN's ON clause (not WHERE) to preserve LEFT JOIN
        // semantics for users with no matching user_points row; the null-safe company match
        // avoids `IS NOT DISTINCT FROM`, which SQLite doesn't support.
        DB::statement(<<<'SQL'
            CREATE VIEW company_user_directory AS
            SELECT
                u.id AS user_id,
                u.name AS name,
                u.email AS email,
                u.role AS role,
                u.is_coach AS is_coach,
                u.is_admin AS is_admin,
                u.number AS number,
                u.created_at AS user_created_at,
                c.id AS company_id,
                c.name AS company_name,
                c.code AS company_code,
                c.is_active AS company_is_active,
                latest.user_total_score AS current_points,
                latest.date AS current_points_as_of
            FROM users u
            LEFT JOIN companies c ON c.id = u.company_id
            LEFT JOIN (
                SELECT
                    up.user_id,
                    up.company_id,
                    up.user_total_score,
                    up.date,
                    ROW_NUMBER() OVER (
                        PARTITION BY up.user_id, up.company_id
                        ORDER BY up.date DESC, up.updated_at DESC
                    ) AS rn
                FROM user_points up
            ) latest
                ON latest.user_id = u.id
                AND (latest.company_id = u.company_id OR (latest.company_id IS NULL AND u.company_id IS NULL))
                AND latest.rn = 1
            ORDER BY (c.name IS NULL), c.name, u.name
        SQL);
    }

    public function down(): void
    {
        DB::statement('DROP VIEW IF EXISTS company_user_directory');
    }
};
