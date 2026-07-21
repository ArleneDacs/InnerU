<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CalorieDay extends Model
{
    protected $table = 'calorie_days';

    protected $fillable = [
        'user_id',
        'date',
        'daily_goal',
        'total_calories',
        'total_protein',
        'total_carbs',
        'total_fat',
        'meal_count',
        'water_glasses',
        'water_goal',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'daily_goal' => 'integer',
            'total_calories' => 'integer',
            'total_protein' => 'integer',
            'total_carbs' => 'integer',
            'total_fat' => 'integer',
            'meal_count' => 'integer',
            'water_glasses' => 'integer',
            'water_goal' => 'integer',
        ];
    }
}
