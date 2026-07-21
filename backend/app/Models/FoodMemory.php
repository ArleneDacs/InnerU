<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FoodMemory extends Model
{
    protected $table = 'food_memories';

    protected $fillable = [
        'user_id',
        'key',
        'display_name',
        'lookup_name',
        'calories',
        'protein',
        'carbs',
        'fat',
        'source',
    ];

    protected function casts(): array
    {
        return [
            'calories' => 'integer',
            'protein' => 'integer',
            'carbs' => 'integer',
            'fat' => 'integer',
        ];
    }
}
