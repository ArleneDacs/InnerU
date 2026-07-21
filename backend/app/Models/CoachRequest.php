<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CoachRequest extends Model
{
    protected $table = 'coach_requests';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'coach_id',
        'coach_name',
        'coach_email',
        'mentee_id',
        'mentee_name',
        'mentee_email',
        'applicant_role',
        'applicant_is_coach',
        'applying_as',
        'status',
        'group_id',
        'group_name',
        'company_code',
        'company_name',
        'accepted_at',
    ];

    protected function casts(): array
    {
        return [
            'applicant_is_coach' => 'boolean',
            'accepted_at' => 'datetime',
        ];
    }
}
