<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CoachMentee extends Model
{
    protected $table = 'coach_mentees';

    protected $fillable = [
        'coach_id',
        'mentee_id',
        'mentee_name',
        'mentee_email',
        'team_name',
        'group_id',
        'group_name',
    ];
}
