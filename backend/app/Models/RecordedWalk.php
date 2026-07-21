<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class RecordedWalk extends Model
{
    protected $table = 'recorded_walks';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'user_id',
        'username',
        'started_at',
        'ended_at',
        'step_count',
        'distance_meters',
        'elapsed_seconds',
        'route_points',
        'interrupted',
    ];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
            'step_count' => 'integer',
            'distance_meters' => 'decimal:2',
            'elapsed_seconds' => 'integer',
            'route_points' => 'array',
            'interrupted' => 'boolean',
        ];
    }
}
