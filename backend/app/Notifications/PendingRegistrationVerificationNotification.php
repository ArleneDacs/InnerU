<?php

namespace App\Notifications;

use App\Models\PendingRegistration;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Notification;

class PendingRegistrationVerificationNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public PendingRegistration $registration,
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Verify your InnerU email')
            ->view('emails.inneru-email-verification', [
                'name' => $this->registration->name,
                'email' => $this->registration->email,
                'actionUrl' => $this->registration->verificationUrl(),
                'logoPath' => base_path('../assets/images/icon.png'),
            ]);
    }
}
