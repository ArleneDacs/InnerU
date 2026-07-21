<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DailyCheckIn extends Model
{
    protected $table = 'daily_check_ins';

    protected $fillable = [
        'user_id',
        'username',
        'date',
        'rating',
        'wins_today',
        'challenges',
        'lessons_learned',
        'gratitude',
        'tomorrow_focus',
        'last_filed_at',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'last_filed_at' => 'datetime',
            'rating' => 'integer',
        ];
    }
}
