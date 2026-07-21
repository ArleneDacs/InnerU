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
        'due_date',
        'tag',
        'is_completed',
        'completed_at',
        'sub_tasks',
    ];

    protected $casts = [
        'due_date' => 'date',
        'is_completed' => 'boolean',
        'completed_at' => 'datetime',
        'sub_tasks' => 'array',
    ];

    public $incrementing = false;

    protected $keyType = 'string';
}
