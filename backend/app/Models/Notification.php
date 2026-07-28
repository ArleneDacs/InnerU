<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

// Note: this is a plain first-class Eloquent model for rows in our own
// `notifications` table (in-app notification feed, polled by the client).
// It is unrelated to Laravel's built-in Illuminate\Notifications channel
// system (Notifiable trait, App\Notifications\* classes) used elsewhere
// for things like password reset emails.
class Notification extends Model
{
    protected $table = 'notifications';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'user_id',
        'type',
        'title',
        'body',
        'data',
        'read_at',
    ];

    protected function casts(): array
    {
        return [
            'data' => 'array',
            'read_at' => 'datetime',
        ];
    }

    /**
     * Create a notification for the given recipient in a single call.
     *
     * @param  array<string, mixed>|null  $data
     */
    public static function createFor(
        string $userId,
        string $type,
        string $title,
        ?string $body = null,
        ?array $data = null,
    ): self {
        return static::create([
            'id' => (string) Str::uuid(),
            'user_id' => $userId,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data,
        ]);
    }
}
