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
            ->view('emails.inneru-password-reset', [
                'email' => $this->email,
                'actionUrl' => $resetUrl,
                'logoPath' => base_path('../assets/images/icon.png'),
            ]);
    }
}
