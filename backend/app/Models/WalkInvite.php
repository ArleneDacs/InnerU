<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalkInvite extends Model
{
    protected $table = 'walk_invites';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'walk_session_id',
        'from_user_id',
        'from_username',
        'to_user_id',
        'to_username',
        'status',
    ];
}
