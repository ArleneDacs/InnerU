<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class GoalUpdate extends Model
{
    protected $table = 'goal_updates';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'goal_id',
        'author_id',
        'progress_from',
        'progress_to',
        'status_from',
        'status_to',
        'note',
    ];

    protected function casts(): array
    {
        return [
            'progress_from' => 'integer',
            'progress_to' => 'integer',
        ];
    }
}
