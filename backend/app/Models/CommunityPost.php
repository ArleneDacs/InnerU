<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CommunityPost extends Model
{
    protected $fillable = [
        'firestore_id',
        'user_id',
        'username',
        'title',
        'note',
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
            'saved' => 'boolean',
        ];
    }
}
