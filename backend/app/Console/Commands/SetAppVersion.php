<?php

namespace App\Console\Commands;

use App\Models\AppVersion;
use Illuminate\Console\Command;

class SetAppVersion extends Command
{
    protected $signature = 'app:set-version {platform : "ios" or "android"} {version : version string (ios) or version code integer (android)} {storeUrl? : optional store URL override} {--required : Make this update blocking} {--optional : Allow users to defer this update}';

    protected $description = 'Manually set the latest published version and, optionally, whether that update is required.';

    public function handle(): int
    {
        $platform = strtolower((string) $this->argument('platform'));
        $version = (string) $this->argument('version');
        $storeUrl = $this->argument('storeUrl');

        if (! in_array($platform, ['ios', 'android'], true)) {
            $this->error('Platform must be "ios" or "android".');

            return self::FAILURE;
        }

        if ($this->option('required') && $this->option('optional')) {
            $this->error('Choose either --required or --optional, not both.');

            return self::FAILURE;
        }

        $updateRequired = $this->option('required')
            ? true
            : ($this->option('optional') ? false : null);

        $appVersion = AppVersion::current();

        if ($platform === 'ios') {
            $appVersion->ios_latest_version = $version;
            if ($storeUrl !== null) {
                $appVersion->ios_store_url = $storeUrl;
            }
            if ($updateRequired !== null) {
                $appVersion->ios_update_required = $updateRequired;
            }
        } else {
            if (! ctype_digit($version)) {
                $this->error('Android version must be an integer version code, e.g. 35.');

                return self::FAILURE;
            }
            $appVersion->android_latest_version_code = (int) $version;
            if ($storeUrl !== null) {
                $appVersion->android_store_url = $storeUrl;
            }
            if ($updateRequired !== null) {
                $appVersion->android_update_required = $updateRequired;
            }
        }

        $appVersion->save();

        $this->info("Updated {$platform} latest version to {$version}.");

        return self::SUCCESS;
    }
}
