<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CalorieEntry extends Model
{
    protected $table = 'calorie_entries';

    protected $fillable = [
        'user_id',
        'calorie_day_id',
        'date',
        'meal',
        'meal_type',
        'calories',
        'protein',
        'carbs',
        'fat',
        'quantity',
        'measurement_unit',
        'photo_url',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'calories' => 'integer',
            'protein' => 'integer',
            'carbs' => 'integer',
            'fat' => 'integer',
            'quantity' => 'decimal:2',
        ];
    }
}
