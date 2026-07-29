<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MeetingAttendance extends Model
{
    protected $table = 'meeting_attendances';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'meeting_id',
        'mentee_id',
        'joined_at',
    ];

    protected function casts(): array
    {
        return [
            'joined_at' => 'datetime',
        ];
    }
}
