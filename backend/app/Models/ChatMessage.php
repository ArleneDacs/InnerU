<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ChatMessage extends Model
{
    protected $table = 'chat_messages';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'chat_room_id',
        'sender_id',
        'sender_name',
        'message',
        'image_url',
        'sender_profile_pic',
        'timestamp',
        'client_timestamp',
    ];

    protected function casts(): array
    {
        return [
            'timestamp' => 'datetime',
            'client_timestamp' => 'datetime',
        ];
    }
}
