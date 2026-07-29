<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StepSubmission extends Model
{
    protected $table = 'step_submissions';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'user_id',
        'steps',
        'date',
        'proof_url',
        'note',
        'status',
        'decline_reason',
        'reviewed_by',
        'reviewed_at',
    ];

    protected function casts(): array
    {
        return [
            'steps' => 'integer',
            'date' => 'date',
            'reviewed_at' => 'datetime',
        ];
    }
}
