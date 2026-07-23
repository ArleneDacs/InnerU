<?php

namespace Tests\Unit;

use App\Models\PendingRegistration;
use App\Notifications\PendingRegistrationVerificationNotification;
use Mockery;
use Tests\TestCase;

class PendingRegistrationVerificationTest extends TestCase
{
    public function test_send_verification_email_returns_true_when_notification_dispatches(): void
    {
        $registration = Mockery::mock(PendingRegistration::class)->makePartial();
        $registration->shouldReceive('notify')->once()->andReturnNull();

        $this->assertTrue($registration->sendVerificationEmail());
    }

    public function test_send_verification_email_returns_false_when_notification_throws(): void
    {
        $registration = Mockery::mock(PendingRegistration::class)->makePartial();
        $registration->shouldReceive('notify')->once()->andThrow(new \RuntimeException('SMTP down'));

        $this->assertFalse($registration->sendVerificationEmail());
    }

    public function test_pending_registration_verification_notification_is_not_queued(): void
    {
        $implements = class_implements(PendingRegistrationVerificationNotification::class);

        $this->assertNotContains(\Illuminate\Contracts\Queue\ShouldQueue::class, $implements);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }
}
