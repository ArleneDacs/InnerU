<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class ApiResetPasswordNotification extends Notification
{
    use Queueable;

    public function __construct(
        public string $token,
        public string $email,
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $resetUrl = rtrim((string) config('app.url'), '/').'/password-reset?mode=resetPassword&token='
            .urlencode($this->token).'&email='.urlencode($this->email);

        return (new MailMessage)
            ->subject('Reset your InnerU password')
            ->line('We received a request to reset your password.')
            ->action('Reset Password', $resetUrl)
            ->line('If you did not request this, you can ignore this email.');
    }
}
