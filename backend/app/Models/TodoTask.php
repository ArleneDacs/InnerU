<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TodoTask extends Model
{
    protected $table = 'todo_tasks';

    protected $fillable = [
        'id',
        'user_id',
        'title',
        'description',
        'goal_type',
        'start_date',
        'due_date',
        'tag',
        'is_completed',
        'completed_at',
        'completion_dates',
        'sub_tasks',
    ];

    protected $casts = [
        'goal_type' => 'string',
        'start_date' => 'date',
        'due_date' => 'date',
        'is_completed' => 'boolean',
        'completed_at' => 'datetime',
        'completion_dates' => 'array',
        'sub_tasks' => 'array',
    ];

    public $incrementing = false;

    protected $keyType = 'string';
}
