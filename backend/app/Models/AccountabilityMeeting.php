<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AccountabilityMeeting extends Model
{
    protected $table = 'accountability_meetings';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'coach_id',
        'group_id',
        'title',
        'zoom_link',
        'notes',
        'scheduled_at',
        'day_before_notified_at',
        'day_of_notified_at',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'day_before_notified_at' => 'datetime',
            'day_of_notified_at' => 'datetime',
        ];
    }
}
