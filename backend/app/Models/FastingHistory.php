<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FastingHistory extends Model
{
    protected $table = 'fasting_history';

    protected $fillable = [
        'firestore_id',
        'user_id',
        'target_hours',
        'start_time',
        'planned_end_time',
        'finished_at',
        'completed_hours',
        'completed_target',
    ];

    protected function casts(): array
    {
        return [
            'start_time' => 'datetime',
            'planned_end_time' => 'datetime',
            'finished_at' => 'datetime',
            'completed_hours' => 'decimal:2',
            'completed_target' => 'boolean',
        ];
    }
}
