<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CoachMentee extends Model
{
    protected $table = 'coach_mentees';

    protected $fillable = [
        'coach_id',
        'mentee_id',
        'mentee_name',
        'mentee_email',
        'team_name',
        'group_id',
        'group_name',
    ];

    /**
     * Distinct coach ids currently assigned to a mentee. A mentee can have
     * more than one coach (e.g. both coaches of a 2-coach group, or two
     * separate individual assignments), so this returns a list rather than
     * a single id.
     *
     * @return array<int, string>
     */
    public static function coachIdsForMentee(string $menteeId): array
    {
        return static::query()
            ->where('mentee_id', $menteeId)
            ->pluck('coach_id')
            ->map(static fn ($coachId) => (string) $coachId)
            ->filter()
            ->unique()
            ->values()
            ->all();
    }
}
