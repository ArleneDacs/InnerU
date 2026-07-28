<?php

use App\Models\CoachGroup;
use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('coach_groups', function (Blueprint $table): void {
            $table->string('company_id')->nullable()->after('coach_id');
        });

        // Backfill existing groups: stamp each group's company_id from its
        // own coach's current company, the same way a newly-created group
        // does. Groups whose coach has no resolvable company are left
        // null (matches how a new group would come out too).
        CoachGroup::query()
            ->whereNull('company_id')
            ->get()
            ->each(function (CoachGroup $group): void {
                $coach = User::query()->find($group->coach_id);
                if ($coach === null) {
                    return;
                }

                $companyId = trim((string) ($coach->active_company_id ?? ''));
                if ($companyId === '') {
                    $companyId = trim((string) ($coach->company_id ?? ''));
                }

                if ($companyId === '') {
                    return;
                }

                $group->company_id = $companyId;
                $group->save();
            });
    }

    public function down(): void
    {
        Schema::table('coach_groups', function (Blueprint $table): void {
            $table->dropColumn('company_id');
        });
    }
};
