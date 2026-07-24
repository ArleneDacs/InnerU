<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Notifications\ApiResetPasswordNotification;
use Database\Factories\UserFactory;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements MustVerifyEmail
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'apple_user_id',
        'number',
        'role',
        'is_coach',
        'is_admin',
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
        'fasting_target_hours',
        'fasting_start_at',
        'fasting_end_at',
        'fasting_last_completed_at',
        'meditation_streak_current',
        'meditation_streak_longest',
        'meditation_streak_last_date',
        'meditation_streak_rewards',
        'steps_streak_current',
        'steps_streak_longest',
        'steps_streak_last_date',
        'steps_streak_rewards',
        'exercise_streak_current',
        'exercise_streak_longest',
        'exercise_streak_last_date',
        'exercise_streak_rewards',
        'fasting_streak_current',
        'fasting_streak_longest',
        'fasting_streak_last_date',
        'fasting_streak_rewards',
        'daily_tracker_items',
        'birthdate',
        'profile_pic',
        'email_verified_at',
        'password',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'birthdate' => 'date',
            'is_coach' => 'boolean',
            'is_admin' => 'boolean',
            'has_company' => 'boolean',
            'company_memberships' => 'array',
            'company_ids' => 'array',
            'company_codes' => 'array',
            'daily_step_goal' => 'integer',
            'fasting_target_hours' => 'integer',
            'fasting_start_at' => 'datetime',
            'fasting_end_at' => 'datetime',
            'fasting_last_completed_at' => 'datetime',
            'meditation_streak_current' => 'integer',
            'meditation_streak_longest' => 'integer',
            'meditation_streak_rewards' => 'array',
            'steps_streak_current' => 'integer',
            'steps_streak_longest' => 'integer',
            'steps_streak_rewards' => 'array',
            'exercise_streak_current' => 'integer',
            'exercise_streak_longest' => 'integer',
            'exercise_streak_rewards' => 'array',
            'fasting_streak_current' => 'integer',
            'fasting_streak_longest' => 'integer',
            'fasting_streak_rewards' => 'array',
            'daily_tracker_items' => 'array',
            'password' => 'hashed',
        ];
    }

    public function sendPasswordResetNotification($token): void
    {
        $this->notify(new ApiResetPasswordNotification($token, $this->email));
    }
}
