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
        'firestore_id',
        'coach_id',
        'company_id',
        'coach_ids',
        'name',
        'member_ids',
        'member_count',
        'company_code',
        'company_name',
        'photo_url',
    ];

    protected function casts(): array
    {
        return [
            'coach_ids' => 'array',
            'member_ids' => 'array',
            'member_count' => 'integer',
        ];
    }
}
