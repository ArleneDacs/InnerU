<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'google' => [
        'web_client_id' => env(
            'GOOGLE_WEB_CLIENT_ID',
            '609604667702-2898tlqiuhgt69viubl09cq4ninu78g9.apps.googleusercontent.com'
        ),
        'ios_client_id' => env(
            'GOOGLE_IOS_CLIENT_ID',
            '609604667702-m3tcf9hqg5mro2d30jju1qmj0beti6mm.apps.googleusercontent.com'
        ),
        'android_client_id' => env(
            'GOOGLE_ANDROID_CLIENT_ID',
            '609604667702-at8ps5hqcibgnrskrbeebcjocatrss7g.apps.googleusercontent.com'
        ),
    ],

    'apple' => [
        'bundle_id' => env('APPLE_BUNDLE_ID', 'com.valenin.inneru'),
        'service_id' => env('APPLE_SERVICE_ID', 'com.valenin.inneru'),
    ],

    'google_play' => [
        'package_name' => env('GOOGLE_PLAY_PACKAGE_NAME', 'com.valenin.inneru'),
        'credentials_path' => env('GOOGLE_PLAY_CREDENTIALS_PATH'),
    ],

    'onesignal' => [
        'app_id' => env('ONESIGNAL_APP_ID'),
        'rest_api_key' => env('ONESIGNAL_REST_API_KEY'),
    ],

    'firebase_scrypt' => [
        'node_verifier_path' => base_path('scripts/firebase-auth-verify/verify.js'),
        'hash_config_path' => env('FIREBASE_HASH_CONFIG_PATH', storage_path('app/firestore-snapshot/hash-config.json')),
    ],

];
