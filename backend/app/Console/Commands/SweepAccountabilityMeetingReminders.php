<?php

namespace App\Console\Commands;

use App\Services\AccountabilityMeetingReminderService;
use Illuminate\Console\Command;

class SweepAccountabilityMeetingReminders extends Command
{
    protected $signature = 'meetings:sweep-reminders';

    protected $description = 'Send "day before" / "day of" in-app reminders for accountability meetings.';

    public function handle(AccountabilityMeetingReminderService $reminderService): int
    {
        $reminderService->sweepDueReminders();

        $this->info('Accountability meeting reminders swept.');

        return self::SUCCESS;
    }
}
