<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NoteComment extends Model
{
    protected $fillable = [
        'community_post_id',
        'user_id',
        'username',
        'comment',
    ];
}
