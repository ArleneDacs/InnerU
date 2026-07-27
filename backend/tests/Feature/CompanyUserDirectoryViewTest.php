<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CompanyUserDirectoryViewTest extends TestCase
{
    use RefreshDatabase;

    public function test_view_lists_a_user_with_their_company_and_latest_points(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GENCYS',
        ]);

        $user = User::factory()->create([
            'name' => 'Gencys Member',
            'company_id' => $company->id,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-20',
            'username' => $user->name,
            'company_id' => $company->id,
            'user_total_score' => 40,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-25',
            'username' => $user->name,
            'company_id' => $company->id,
            'user_total_score' => 55,
        ]);

        $row = DB::table('company_user_directory')
            ->where('user_id', $user->id)
            ->first();

        $this->assertNotNull($row);
        $this->assertSame($company->id, $row->company_id);
        $this->assertSame('Gencys', $row->company_name);
        $this->assertSame('GENCYS', $row->company_code);
        $this->assertEquals(55, $row->current_points);
        $this->assertSame('2026-07-25', $row->current_points_as_of);
    }

    public function test_view_keeps_a_second_company_separate(): void
    {
        $gencys = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GENCYS',
        ]);
        $abundance = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABUNDANCE',
        ]);

        User::factory()->create(['name' => 'Gencys User', 'company_id' => $gencys->id]);
        User::factory()->create(['name' => 'Abundance User', 'company_id' => $abundance->id]);

        $gencysRows = DB::table('company_user_directory')
            ->where('company_code', 'GENCYS')
            ->get();
        $abundanceRows = DB::table('company_user_directory')
            ->where('company_code', 'ABUNDANCE')
            ->get();

        $this->assertCount(1, $gencysRows);
        $this->assertSame('Gencys User', $gencysRows->first()->name);
        $this->assertCount(1, $abundanceRows);
        $this->assertSame('Abundance User', $abundanceRows->first()->name);
    }

    public function test_view_includes_a_user_with_no_company_and_no_points(): void
    {
        $user = User::factory()->create([
            'name' => 'Unassigned User',
            'company_id' => null,
        ]);

        $row = DB::table('company_user_directory')
            ->where('user_id', $user->id)
            ->first();

        $this->assertNotNull($row);
        $this->assertNull($row->company_id);
        $this->assertNull($row->company_name);
        $this->assertNull($row->company_code);
        $this->assertNull($row->current_points);
        $this->assertNull($row->current_points_as_of);
    }

    public function test_view_isolates_points_per_company_for_a_user_in_multiple_companies(): void
    {
        $companyA = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GENCYS',
        ]);
        $companyB = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABUNDANCE',
        ]);

        $user = User::factory()->create([
            'name' => 'Multi Company User',
            'company_id' => $companyA->id,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-25',
            'username' => $user->name,
            'company_id' => $companyA->id,
            'user_total_score' => 55,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-26',
            'username' => $user->name,
            'company_id' => $companyB->id,
            'user_total_score' => 999,
        ]);

        $row = DB::table('company_user_directory')
            ->where('user_id', $user->id)
            ->first();

        $this->assertNotNull($row);
        $this->assertSame($companyA->id, $row->company_id);
        $this->assertSame('GENCYS', $row->company_code);
        $this->assertEquals(55, $row->current_points);
        $this->assertSame('2026-07-25', $row->current_points_as_of);
    }
}
