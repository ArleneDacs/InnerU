<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ChatRoom extends Model
{
    protected $table = 'chat_rooms';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'is_group_chat',
        'coach_id',
        'coach_name',
        'user_id',
        'user_name',
        'group_name',
        'group_profile_pic',
        'last_message',
        'last_message_time',
        'last_sender_id',
        'participants',
        'participant_names',
        'participant_profiles',
        'unread_counts',
        'last_read_at',
        'company_id',
        'company_code',
        'company_name',
    ];

    protected function casts(): array
    {
        return [
            'is_group_chat' => 'boolean',
            'participants' => 'array',
            'participant_names' => 'array',
            'participant_profiles' => 'array',
            'unread_counts' => 'array',
            'last_read_at' => 'array',
            'last_message_time' => 'datetime',
        ];
    }
}
