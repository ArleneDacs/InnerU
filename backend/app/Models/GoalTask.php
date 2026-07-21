<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class GoalTask extends Model
{
    protected $table = 'goal_tasks';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'goal_id',
        'title',
        'status',
        'is_complete',
        'due_date',
        'completed_at',
        'sort_order',
        'weight',
    ];

    protected function casts(): array
    {
        return [
            'is_complete' => 'boolean',
            'due_date' => 'datetime',
            'completed_at' => 'datetime',
            'sort_order' => 'integer',
            'weight' => 'integer',
        ];
    }
}
