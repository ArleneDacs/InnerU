<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CommunityPostHeart extends Model
{
    protected $fillable = [
        'community_post_id',
        'user_id',
    ];

    /**
     * The member who left this heart.  Keeping this relation on the reaction
     * model lets the lightweight "who liked this" endpoint load all names in
     * one query instead of resolving one user per heart.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
