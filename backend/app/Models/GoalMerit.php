<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class GoalMerit extends Model
{
    protected $table = 'goal_merits';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'firestore_id',
        'goal_id',
        'user_id',
        'date',
        'amount',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'amount' => 'decimal:2',
        ];
    }
}
