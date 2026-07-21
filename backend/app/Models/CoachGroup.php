<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CoachGroup extends Model
{
    protected $table = 'coach_groups';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'coach_id',
        'name',
        'member_ids',
        'member_count',
        'company_code',
        'company_name',
    ];

    protected function casts(): array
    {
        return [
            'member_ids' => 'array',
            'member_count' => 'integer',
        ];
    }
}
