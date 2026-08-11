<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DailyTracker extends Model
{
    protected $fillable = [
        'user_id',
        'username',
        'date',
        'step_count',
        'step_goal',
        'meditation',
        'steps',
        'call',
        'exercise',
        'learning',
        'add_value',
        'todo_list',
        'call_count',
        'exercise_count',
        'exercise_minutes',
        'learning_count',
        'value_count',
        'todo_list_count',
        'todo_list_score',
        'todo_list_score_daily_contribution',
        'todo_list_included_in_total',
        'user_total_score',
        'custom_daily_tasks',
        'meditation_minutes',
        'company_id',
        'company_code',
        'company_name',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'meditation' => 'boolean',
            'steps' => 'boolean',
            'call' => 'boolean',
            'learning' => 'boolean',
            'add_value' => 'boolean',
            'todo_list' => 'boolean',
            'exercise' => 'boolean',
            'call_count' => 'integer',
            'exercise_count' => 'integer',
            'exercise_minutes' => 'integer',
            'learning_count' => 'integer',
            'value_count' => 'integer',
            'todo_list_count' => 'integer',
            'todo_list_score' => 'integer',
            'todo_list_score_daily_contribution' => 'integer',
            'todo_list_included_in_total' => 'boolean',
            'user_total_score' => 'integer',
            'custom_daily_tasks' => 'array',
            'leaderboard_completed_at' => 'datetime',
        ];
    }
}
