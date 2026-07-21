<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Emotion extends Model
{
    protected $fillable = [
        'user_id',
        'username',
        'emotion',
        'date',
        'history',
        'last_logged_at',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'history' => 'array',
            'last_logged_at' => 'datetime',
        ];
    }
}
