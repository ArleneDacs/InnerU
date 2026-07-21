<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalkSession extends Model
{
    protected $table = 'walk_sessions';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'created_by',
        'created_by_name',
        'status',
        'participant_ids',
        'company_id',
        'company_code',
        'company_name',
    ];

    protected function casts(): array
    {
        return [
            'participant_ids' => 'array',
        ];
    }
}
