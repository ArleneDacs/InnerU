<?php

namespace Tests\Feature;

use App\Models\Company;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class CompanyCodeValidationTest extends TestCase
{
    use RefreshDatabase;

    private const INVALID_COMPANY_CODE_MESSAGE = 'Company code is invalid. Please enter a valid company code.';

    public function test_public_endpoint_accepts_an_active_company_code_case_insensitively(): void
    {
        Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
            'is_active' => true,
        ]);

        $this->postJson('/api/auth/company-code/validate', [
            'company_code' => ' gen0kus ',
        ])->assertOk()
            ->assertExactJson(['valid' => true]);
    }

    public function test_public_endpoint_rejects_an_unknown_company_code_with_the_signup_message(): void
    {
        $response = $this->postJson('/api/auth/company-code/validate', [
            'company_code' => 'DOES-NOT-EXIST',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);
    }

    public function test_public_endpoint_rejects_an_inactive_company_code(): void
    {
        Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Inactive Company',
            'code' => 'INACTIVE',
            'is_active' => false,
        ]);

        $response = $this->postJson('/api/auth/company-code/validate', [
            'company_code' => 'inactive',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);
    }

    public function test_public_endpoint_uses_the_same_message_when_the_code_is_blank(): void
    {
        $response = $this->postJson('/api/auth/company-code/validate', [
            'company_code' => '',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);
    }
}
