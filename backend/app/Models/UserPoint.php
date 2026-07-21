<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserPoint extends Model
{
    protected $table = 'user_points';

    protected $fillable = [
        'user_id',
        'date',
        'username',
        'total_points',
        'activity_points',
        'daily_tracker_score',
        'todo_list_score',
        'todo_list_score_daily_contribution',
        'todo_list_included_in_total',
        'user_total_score',
        'task_points',
        'tasks',
        'server',
        'company_id',
        'company_code',
        'company_name',
        'activity_counts',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'total_points' => 'decimal:2',
            'todo_list_included_in_total' => 'boolean',
            'task_points' => 'array',
            'tasks' => 'array',
            'activity_counts' => 'array',
        ];
    }
}
