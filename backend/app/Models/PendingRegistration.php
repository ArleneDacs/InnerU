<?php

namespace App\Models;

use App\Notifications\PendingRegistrationVerificationNotification;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\URL;

class PendingRegistration extends Model
{
    use Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'apple_user_id',
        'encrypted_password',
        'number',
        'role',
        'is_coach',
        'company_code',
        'company_name',
        'has_company',
        'company_id',
        'active_company_id',
        'active_company_code',
        'active_company_name',
        'active_company_score_mode',
        'score_mode',
        'company_memberships',
        'company_ids',
        'company_codes',
        'daily_step_goal',
        'daily_tracker_items',
        'birthdate',
        'profile_pic',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'is_coach' => 'boolean',
            'has_company' => 'boolean',
            'company_memberships' => 'array',
            'company_ids' => 'array',
            'company_codes' => 'array',
            'daily_step_goal' => 'integer',
            'daily_tracker_items' => 'array',
            'birthdate' => 'date',
        ];
    }

    public function verificationUrl(): string
    {
        return URL::temporarySignedRoute(
            'verification.verify',
            now()->addDay(),
            [
                'id' => $this->getKey(),
                'hash' => sha1($this->email),
            ]
        );
    }

    /**
     * Build the attributes used to create the verified user account.
     *
     * @return array<string, mixed>
     */
    public function toUserAttributes(): array
    {
        $attributes = [
            'name' => $this->name,
            'email' => $this->email,
            'number' => $this->number,
            'role' => $this->role,
            'is_coach' => $this->is_coach,
            'company_code' => $this->company_code,
            'company_name' => $this->company_name,
            'has_company' => $this->has_company,
            'company_id' => $this->company_id,
            'active_company_id' => $this->active_company_id,
            'active_company_code' => $this->active_company_code,
            'active_company_name' => $this->active_company_name,
            'active_company_score_mode' => $this->active_company_score_mode,
            'score_mode' => $this->score_mode,
            'company_memberships' => $this->company_memberships,
            'company_ids' => $this->company_ids,
            'company_codes' => $this->company_codes,
            'daily_step_goal' => $this->daily_step_goal,
            'daily_tracker_items' => $this->daily_tracker_items,
            'birthdate' => $this->birthdate,
            'profile_pic' => $this->profile_pic,
            'email_verified_at' => now(),
            'password' => Crypt::decryptString($this->encrypted_password),
        ];

        if (Schema::hasColumn('users', 'apple_user_id') && filled($this->apple_user_id)) {
            $attributes['apple_user_id'] = $this->apple_user_id;
        }

        return $attributes;
    }

    public function sendVerificationEmail(): bool
    {
        try {
            $this->notify(new PendingRegistrationVerificationNotification($this));

            return true;
        } catch (\Throwable $throwable) {
            report($throwable);

            return false;
        }
    }
}
