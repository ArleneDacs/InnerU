<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Goal extends Model
{
    protected $table = 'goals';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'firestore_id',
        'user_id',
        'company_id',
        'category',
        'title',
        'description',
        'notes',
        'status',
        'goal_type',
        'direction',
        'target_value',
        'current_value',
        'unit',
        'target_period',
        'start_date',
        'target_date',
        'completed_at',
        'progress',
    ];

    protected function casts(): array
    {
        return [
            'target_value' => 'decimal:2',
            'current_value' => 'decimal:2',
            'start_date' => 'date:Y-m-d',
            'target_date' => 'date:Y-m-d',
            'completed_at' => 'datetime',
            'progress' => 'integer',
        ];
    }
}
