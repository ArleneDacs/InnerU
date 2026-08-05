<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NoteComment extends Model
{
    protected $fillable = [
        'firestore_id',
        'community_post_id',
        'user_id',
        'parent_id',
        'username',
        'comment',
        'mentions',
    ];

    protected function casts(): array
    {
        return ['mentions' => 'array'];
    }

    public function user(): \Illuminate\Database\Eloquent\Relations\BelongsTo
    {
        return $this->belongsTo(\App\Models\User::class);
    }

    public function reactions(): \Illuminate\Database\Eloquent\Relations\HasMany
    {
        return $this->hasMany(\App\Models\CommentReaction::class);
    }

    public function parent(): \Illuminate\Database\Eloquent\Relations\BelongsTo
    {
        return $this->belongsTo(NoteComment::class, 'parent_id');
    }

    public function replies(): \Illuminate\Database\Eloquent\Relations\HasMany
    {
        return $this->hasMany(NoteComment::class, 'parent_id');
    }
}
