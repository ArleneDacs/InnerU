<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Best-effort supplement to the opportunistic reminder sweep that already
// runs inside AccountabilityMeetingController::index()/mine() on every
// poll of a coach's or mentee's meetings list. This scheduled command
// covers the case where nobody happens to poll around the reminder
// window, but it only actually fires if the server's crontab runs
// Laravel's scheduler:
//   * * * * * php artisan schedule:run >> /dev/null 2>&1
Schedule::command('meetings:sweep-reminders')->everyFifteenMinutes();
