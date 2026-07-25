<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class GoalComment extends Model
{
    protected $table = 'goal_comments';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'firestore_id',
        'goal_id',
        'author_id',
        'body',
        'is_private',
    ];

    protected function casts(): array
    {
        return [
            'is_private' => 'boolean',
        ];
    }
}
