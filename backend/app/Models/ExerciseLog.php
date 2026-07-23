<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ExerciseLog extends Model
{
    protected $table = 'exercise_logs';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'user_id',
        'username',
        'type',
        'duration_minutes',
        'duration_seconds',
        'intensity',
        'notes',
        'start_photo_url',
        'end_photo_url',
        'date',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'intensity' => 'integer',
            'duration_minutes' => 'integer',
            'duration_seconds' => 'integer',
        ];
    }
}
