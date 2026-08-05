<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CommunityPost extends Model
{
    protected $fillable = [
        'firestore_id',
        'user_id',
        'username',
        'title',
        'note',
        'mentions',
        'color',
        'category',
        'saved',
        'company_id',
        'company_code',
        'company_name',
    ];

    protected function casts(): array
    {
        return [
            'note' => 'array',
            'mentions' => 'array',
            'saved' => 'boolean',
        ];
    }

    public function hearts(): HasMany
    {
        return $this->hasMany(CommunityPostHeart::class);
    }
}
