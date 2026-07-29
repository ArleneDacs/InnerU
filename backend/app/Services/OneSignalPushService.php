<?php

namespace App\Services;

use App\Models\Notification;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class OneSignalPushService
{
    public function send(Notification $notification): void
    {
        $appId = (string) config('services.onesignal.app_id', '');
        $restApiKey = (string) config('services.onesignal.rest_api_key', '');

        if ($appId === '' || $restApiKey === '') {
            Log::debug('OneSignal push is disabled. Missing credentials.');
            return;
        }

        $payload = [
            'app_id' => $appId,
            'target_channel' => 'push',
            'include_aliases' => [
                'external_id' => [(string) $notification->user_id],
            ],
            'headings' => [
                'en' => (string) $notification->title,
            ],
            'contents' => [
                'en' => (string) ($notification->body ?: $notification->title),
            ],
            'data' => array_merge(
                is_array($notification->data) ? $notification->data : [],
                [
                    'notification_id' => (string) $notification->id,
                    'type' => (string) $notification->type,
                    'user_id' => (string) $notification->user_id,
                    'title' => (string) $notification->title,
                    'body' => $notification->body,
                ]
            ),
        ];

        try {
            $response = Http::withHeaders([
                'Authorization' => 'Key '.$restApiKey,
                'Accept' => 'application/json',
                'Content-Type' => 'application/json',
            ])->post('https://api.onesignal.com/notifications?c=push', $payload);

            if ($response->failed()) {
                Log::warning('OneSignal push delivery failed.', [
                    'notification_id' => (string) $notification->id,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Throwable $throwable) {
            Log::warning('OneSignal push delivery threw an exception.', [
                'notification_id' => (string) $notification->id,
                'error' => $throwable->getMessage(),
            ]);
        }
    }
}
