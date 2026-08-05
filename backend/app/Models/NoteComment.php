<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NoteComment extends Model
{
    protected $fillable = [
        'firestore_id',
        'community_post_id',
        'user_id',
        'username',
        'comment',
    ];

    public function user(): \Illuminate\Database\Eloquent\Relations\BelongsTo
    {
        return $this->belongsTo(\App\Models\User::class);
    }

    public function reactions(): \Illuminate\Database\Eloquent\Relations\HasMany
    {
        return $this->hasMany(\App\Models\CommentReaction::class);
    }
}
