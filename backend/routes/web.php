<?php

use App\Models\PendingRegistration;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Schema;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/password-reset', function (Request $request) {
    $frontendUrl = rtrim((string) config('app.frontend_url'), '/');
    $query = $request->getQueryString();
    $target = $frontendUrl.'/';

    if (is_string($query) && $query !== '') {
        $target .= '?'.$query;
    }

    return redirect()->away($target);
});

Route::get('/email/verify/{id}/{hash}', function (Request $request, string $id, string $hash) {
    $pending = PendingRegistration::find($id);

    if ($pending !== null) {
        if (! hash_equals($hash, sha1($pending->email))) {
            abort(403);
        }

        DB::transaction(function () use ($pending): void {
            $user = User::where('email', $pending->email)->first();

            if ($user === null) {
                User::create($pending->toUserAttributes());
            } elseif ($user->email_verified_at === null) {
                $updates = [
                    'name' => $pending->name,
                    'number' => $pending->number,
                    'role' => $pending->role,
                    'is_coach' => $pending->is_coach,
                    'company_code' => $pending->company_code,
                    'company_name' => $pending->company_name,
                    'has_company' => $pending->has_company,
                    'company_id' => $pending->company_id,
                    'active_company_id' => $pending->active_company_id,
                    'active_company_code' => $pending->active_company_code,
                    'active_company_name' => $pending->active_company_name,
                    'active_company_score_mode' => $pending->active_company_score_mode,
                    'score_mode' => $pending->score_mode,
                    'company_memberships' => $pending->company_memberships,
                    'company_ids' => $pending->company_ids,
                    'company_codes' => $pending->company_codes,
                    'daily_step_goal' => $pending->daily_step_goal,
                    'daily_tracker_items' => $pending->daily_tracker_items,
                    'birthdate' => $pending->birthdate,
                    'profile_pic' => $pending->profile_pic,
                    'email_verified_at' => now(),
                ];

                if (Schema::hasColumn('users', 'apple_user_id') && filled($pending->apple_user_id)) {
                    $updates['apple_user_id'] = $pending->apple_user_id;
                }

                $user->forceFill($updates)->save();
            }

            $pending->delete();
        });

        return view('auth.email-verified', [
            'verified' => true,
        ]);
    }

    $user = User::findOrFail($id);

    if (! hash_equals($hash, sha1($user->getEmailForVerification()))) {
        abort(403);
    }

    if ($user->hasVerifiedEmail()) {
        return view('auth.email-verified', [
            'verified' => true,
        ]);
    }

    $user->forceFill([
        'email_verified_at' => now(),
    ])->save();

    return view('auth.email-verified', [
        'verified' => true,
    ]);
})->name('verification.verify');
