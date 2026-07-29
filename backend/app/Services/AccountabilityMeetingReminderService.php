<?php

namespace App\Services;

use App\Models\AccountabilityMeeting;
use App\Models\CoachMentee;
use App\Models\Notification;

// Shared "day before" / "day of" reminder sweep for accountability
// meetings. Called opportunistically from
// AccountabilityMeetingController::index()/mine() (so reminders fire
// whenever anyone polls their meetings list) and from the
// meetings:sweep-reminders Artisan command (a best-effort scheduled
// supplement — see that command for why it isn't the sole mechanism).
//
// Both notify passes are idempotent via the *_notified_at IS NULL guard,
// so calling sweepDueReminders() repeatedly (even many times a minute) is
// safe and cheap — each pass only touches a handful of date-filtered rows.
class AccountabilityMeetingReminderService
{
    public function sweepDueReminders(): void
    {
        $this->notifyDueMeetings(
            dateColumn: 'day_before_notified_at',
            targetDate: now()->addDay()->toDateString(),
            type: 'meeting_reminder_day_before',
            titleFor: fn (AccountabilityMeeting $meeting): string => "Accountability meeting tomorrow: {$meeting->title}",
            body: 'Join with your group tomorrow.',
        );

        $this->notifyDueMeetings(
            dateColumn: 'day_of_notified_at',
            targetDate: now()->toDateString(),
            type: 'meeting_reminder_day_of',
            titleFor: fn (AccountabilityMeeting $meeting): string => "Accountability meeting today: {$meeting->title}",
            body: 'Join with your group today.',
        );
    }

    private function notifyDueMeetings(
        string $dateColumn,
        string $targetDate,
        string $type,
        \Closure $titleFor,
        string $body,
    ): void {
        $meetings = AccountabilityMeeting::query()
            ->whereDate('scheduled_at', $targetDate)
            ->whereNull($dateColumn)
            ->get();

        foreach ($meetings as $meeting) {
            $menteeIds = CoachMentee::query()
                ->where('group_id', $meeting->group_id)
                ->pluck('mentee_id');

            foreach ($menteeIds as $menteeId) {
                Notification::createFor(
                    (string) $menteeId,
                    $type,
                    $titleFor($meeting),
                    $body,
                    [
                        'meetingId' => (string) $meeting->id,
                        'groupId' => (string) $meeting->group_id,
                        'scheduledAt' => $meeting->scheduled_at->toIso8601String(),
                        'zoomLink' => $meeting->zoom_link,
                    ],
                );
            }

            $meeting->forceFill([$dateColumn => now()])->save();
        }
    }
}
