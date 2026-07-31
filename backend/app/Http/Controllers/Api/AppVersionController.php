<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppVersion;
use Illuminate\Http\JsonResponse;

class AppVersionController extends Controller
{
    public function show(): JsonResponse
    {
        $version = AppVersion::current();

        return response()->json([
            'ios' => [
                'latest_version' => $version->ios_latest_version,
                'store_url' => $version->ios_store_url,
            ],
            'android' => [
                'latest_version_code' => $version->android_latest_version_code,
                'store_url' => $version->android_store_url,
            ],
        ]);
    }
}
