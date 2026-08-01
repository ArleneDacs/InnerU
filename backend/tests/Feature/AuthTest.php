<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\PendingRegistration;
use App\Models\User;
use App\Notifications\PendingRegistrationVerificationNotification;
use App\Services\FirebaseScryptVerifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    private const INVALID_COMPANY_CODE_MESSAGE = 'Company code is invalid. Please enter a valid company code.';

    #[DataProvider('signupRoleProvider')]
    public function test_register_stores_a_pending_registration_for_each_role(
        string $role,
        bool $isCoach,
        ?string $companyCode,
        ?string $companyName
    ): void {
        Notification::fake();

        if ($companyCode !== null) {
            Company::create([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'name' => (string) $companyName,
                'code' => $companyCode,
            ]);
        }

        $response = $this->postJson('/api/auth/register', [
            'name' => $role === 'coach' ? 'Coach Member' : 'User Member',
            'email' => "{$role}.member.inneru@gmail.com",
            'password' => 'Password123',
            'number' => '09171234567',
            'role' => $role,
            'company_code' => $companyCode,
            'company_name' => $companyName,
        ]);

        $response->assertCreated()
            ->assertJsonPath('verification_required', true)
            ->assertJsonPath('email', "{$role}.member.inneru@gmail.com")
            ->assertJsonPath('name', $role === 'coach' ? 'Coach Member' : 'User Member');

        $pending = PendingRegistration::where('email', "{$role}.member.inneru@gmail.com")->firstOrFail();

        Notification::assertSentTo($pending, PendingRegistrationVerificationNotification::class);

        $this->assertDatabaseHas('pending_registrations', [
            'email' => "{$role}.member.inneru@gmail.com",
            'name' => $role === 'coach' ? 'Coach Member' : 'User Member',
            'number' => '09171234567',
            'role' => $role,
            'is_coach' => $isCoach,
            'company_code' => $companyCode,
            'company_name' => $companyName,
            'has_company' => $companyCode !== null,
            'encrypted_password' => $pending->encrypted_password,
        ]);

        $this->assertTrue(Crypt::decryptString($pending->encrypted_password) === 'Password123');
    }

    #[DataProvider('loginRoleProvider')]
    public function test_login_returns_a_token_for_verified_users_of_each_role(
        string $role,
        bool $isCoach
    ): void {
        $user = User::factory()->create([
            'name' => $role === 'coach' ? 'Coach Login' : 'User Login',
            'email' => "{$role}.login.inneru@gmail.com",
            'role' => $role,
            'is_coach' => $isCoach,
            'has_company' => $isCoach,
            'company_code' => $isCoach ? 'ACME' : null,
            'company_name' => $isCoach ? 'ACME' : null,
            'company_id' => $isCoach ? 'ACME' : null,
            'active_company_id' => $isCoach ? 'ACME' : null,
            'active_company_code' => $isCoach ? 'ACME' : null,
            'active_company_name' => $isCoach ? 'ACME' : null,
            'email_verified_at' => now(),
            'password' => bcrypt('Password123'),
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'Password123',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.email', $user->email)
            ->assertJsonPath('user.role', $role)
            ->assertJsonPath('user.is_coach', $isCoach)
            ->assertJsonStructure([
                'token_type',
                'token',
                'user' => [
                    'id',
                    'name',
                    'email',
                    'role',
                    'is_coach',
                ],
            ]);

        $this->assertDatabaseMissing('pending_registrations', [
            'email' => $user->email,
        ]);
    }

    public function test_register_stores_a_pending_registration_and_sends_a_verification_email(): void
    {
        Notification::fake();

        Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'ACME',
            'code' => 'ACME',
        ]);

        $response = $this->postJson('/api/auth/register', [
            'name' => 'New Member',
            'email' => 'new.member.inneru@gmail.com',
            'password' => 'Password123',
            'number' => '09171234567',
            'role' => 'user',
            'company_code' => 'ACME',
            'company_name' => 'ACME',
        ]);

        $response->assertCreated()
            ->assertJsonPath('verification_required', true)
            ->assertJsonPath('email', 'new.member.inneru@gmail.com')
            ->assertJsonPath('name', 'New Member');

        $this->assertDatabaseMissing('users', [
            'email' => 'new.member.inneru@gmail.com',
        ]);

        $pending = PendingRegistration::where('email', 'new.member.inneru@gmail.com')->firstOrFail();

        Notification::assertSentTo($pending, PendingRegistrationVerificationNotification::class);

        $this->assertDatabaseHas('pending_registrations', [
            'email' => 'new.member.inneru@gmail.com',
            'name' => 'New Member',
            'number' => '09171234567',
            'role' => 'user',
            'company_code' => 'ACME',
            'company_name' => 'ACME',
            'has_company' => true,
            'encrypted_password' => $pending->encrypted_password,
        ]);

        $this->assertTrue(Crypt::decryptString($pending->encrypted_password) === 'Password123');
    }

    public function test_register_resolves_a_real_company_id_and_name_instead_of_the_raw_code(): void
    {
        Notification::fake();

        $company = Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
        ]);

        $this->postJson('/api/auth/register', [
            'name' => 'Company Member',
            'email' => 'company.member.inneru@gmail.com',
            'password' => 'Password123',
            'number' => '09171234567',
            'role' => 'user',
            'company_code' => ' gen0kus ',
            // The client sends the code as company_name too (matching what
            // the real app was observed sending) - the real company name
            // must win over this, not the other way around.
            'company_name' => 'GEN0KUS',
        ])->assertCreated();

        $pending = PendingRegistration::where('email', 'company.member.inneru@gmail.com')->firstOrFail();

        // Regression: company_id used to be set to the raw code string
        // ("GEN0KUS") instead of the company's real database id, and
        // company_name used to pass through whatever the client sent
        // instead of the real company's display name.
        $this->assertSame($company->id, $pending->company_id);
        $this->assertSame($company->id, $pending->active_company_id);
        $this->assertSame('Gencys', $pending->company_name);
        $this->assertSame('Gencys', $pending->active_company_name);
    }

    public function test_register_rejects_an_unknown_company_code(): void
    {
        Notification::fake();

        $response = $this->postJson('/api/auth/register', [
            'name' => 'Unknown Company Member',
            'email' => 'unknown.company.member.inneru@gmail.com',
            'password' => 'Password123',
            'role' => 'user',
            'company_code' => 'DOES-NOT-EXIST',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);

        $this->assertDatabaseMissing('pending_registrations', [
            'email' => 'unknown.company.member.inneru@gmail.com',
        ]);
    }

    public function test_register_can_continue_without_a_company_even_if_a_stale_code_is_supplied(): void
    {
        Notification::fake();

        $response = $this->postJson('/api/auth/register', [
            'name' => 'Independent Member',
            'email' => 'independent.member.inneru@gmail.com',
            'password' => 'Password123',
            'role' => 'user',
            'company_code' => 'STALE-CODE',
            'company_name' => 'Stale Company',
            'continue_without_company' => true,
        ]);

        $response->assertCreated();

        $this->assertDatabaseHas('pending_registrations', [
            'email' => 'independent.member.inneru@gmail.com',
            'company_code' => null,
            'company_name' => null,
            'company_id' => null,
            'has_company' => false,
        ]);
    }

    public function test_verifying_a_pending_registration_creates_the_user(): void
    {
        $pending = PendingRegistration::create([
            'name' => 'Pending Member',
            'email' => 'pending.inneru@gmail.com',
            'apple_user_id' => 'apple-subject-001',
            'number' => '09170000000',
            'role' => 'user',
            'is_coach' => false,
            'company_code' => 'ACME',
            'company_name' => 'ACME',
            'has_company' => true,
            'company_id' => 'ACME',
            'active_company_id' => 'ACME',
            'active_company_code' => 'ACME',
            'active_company_name' => 'ACME',
            'active_company_score_mode' => null,
            'score_mode' => null,
            'company_memberships' => null,
            'company_ids' => null,
            'company_codes' => null,
            'daily_step_goal' => null,
            'daily_tracker_items' => null,
            'birthdate' => null,
            'profile_pic' => null,
            'encrypted_password' => Crypt::encryptString('Password123'),
        ]);

        $response = $this->get($pending->verificationUrl());

        $response->assertOk()
            ->assertSee('Email verified');

        $this->assertDatabaseMissing('pending_registrations', [
            'email' => 'pending.inneru@gmail.com',
        ]);

        $user = User::where('email', 'pending.inneru@gmail.com')->firstOrFail();

        $this->assertTrue($user->hasVerifiedEmail());
        $this->assertSame('apple-subject-001', $user->apple_user_id);
        $this->assertTrue(Crypt::decryptString($pending->encrypted_password) === 'Password123');
    }

    public function test_login_rejects_pending_registrations_before_verification(): void
    {
        PendingRegistration::create([
            'name' => 'Pending Member',
            'email' => 'pending-login.inneru@gmail.com',
            'number' => null,
            'role' => 'user',
            'is_coach' => false,
            'company_code' => null,
            'company_name' => null,
            'has_company' => false,
            'company_id' => null,
            'active_company_id' => null,
            'active_company_code' => null,
            'active_company_name' => null,
            'active_company_score_mode' => null,
            'score_mode' => null,
            'company_memberships' => null,
            'company_ids' => null,
            'company_codes' => null,
            'daily_step_goal' => null,
            'daily_tracker_items' => null,
            'birthdate' => null,
            'profile_pic' => null,
            'encrypted_password' => Crypt::encryptString('Password123'),
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => 'pending-login.inneru@gmail.com',
            'password' => 'Password123',
        ]);

        $response->assertForbidden()
            ->assertJsonPath('message', 'Please verify your email first.');
    }

    public function test_password_reset_web_route_shows_the_reset_form(): void
    {
        $response = $this->get('/password-reset?mode=resetPassword&token=abc123&email=user%40example.com');

        $response->assertOk()
            ->assertSee('Reset your password')
            ->assertSee('New password')
            ->assertSee('Confirm password')
            ->assertSee('Save new password');
    }

    public function test_password_reset_web_form_updates_the_password(): void
    {
        $user = User::factory()->create([
            'email' => 'reset.user.inneru@gmail.com',
            'password' => bcrypt('OldPassword123'),
            'email_verified_at' => now(),
        ]);

        $token = Password::broker()->createToken($user);

        $response = $this->post('/password-reset', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $response->assertOk()
            ->assertSee('Password updated');

        $this->assertTrue(Hash::check('NewPassword123', $user->fresh()->password));
    }

    public function test_password_reset_web_form_clears_legacy_password_columns(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $token = Password::broker()->createToken($user);

        $response = $this->post('/password-reset', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $response->assertOk();

        $user->refresh();
        $this->assertNull($user->legacy_password_hash);
        $this->assertNull($user->legacy_password_salt);
        $this->assertTrue(Hash::check('NewPassword123', $user->password));
    }

    public function test_login_succeeds_for_a_migrated_account_via_legacy_password_verification(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $this->mock(FirebaseScryptVerifier::class, function ($mock) {
            $mock->shouldReceive('verify')
                ->once()
                ->with('their-old-password', 'stored-hash', 'stored-salt')
                ->andReturn(true);
        });

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'their-old-password',
        ]);

        $response->assertOk();
        $user->refresh();
        $this->assertNull($user->legacy_password_hash);
        $this->assertNull($user->legacy_password_salt);
        $this->assertTrue(Hash::check('their-old-password', $user->password));
    }

    public function test_login_fails_for_a_migrated_account_with_the_wrong_password(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $this->mock(FirebaseScryptVerifier::class, function ($mock) {
            $mock->shouldReceive('verify')->once()->andReturn(false);
        });

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'wrong-password',
        ]);

        $response->assertStatus(401);
        $user->refresh();
        $this->assertNotNull($user->legacy_password_hash, 'legacy hash must survive a failed attempt');
    }

    public function test_password_reset_clears_legacy_password_columns_and_allows_login_with_the_new_password(): void
    {
        $user = User::factory()->create([
            'password' => null,
            'legacy_password_hash' => 'stored-hash',
            'legacy_password_salt' => 'stored-salt',
            'email_verified_at' => now(),
        ]);

        $token = Password::broker()->createToken($user);

        $response = $this->postJson('/api/auth/password/reset', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $response->assertOk()
            ->assertJsonPath('message', 'Password updated successfully.');

        $user->refresh();
        $this->assertNull($user->legacy_password_hash);
        $this->assertNull($user->legacy_password_salt);
        $this->assertTrue(Hash::check('NewPassword123', $user->password));

        $this->mock(FirebaseScryptVerifier::class, function ($mock) {
            $mock->shouldNotReceive('verify');
        });

        $loginResponse = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'NewPassword123',
        ]);

        $loginResponse->assertOk();
    }

    public function test_login_rejects_unverified_email_password_accounts(): void
    {
        $user = User::factory()->create([
            'email' => 'pending.inneru@gmail.com',
            'password' => bcrypt('Password123'),
            'email_verified_at' => null,
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'Password123',
        ]);

        $response->assertForbidden()
            ->assertJsonPath('message', 'Please verify your email first.');
    }

    public function test_google_signup_creates_a_pending_registration_and_sends_verification_email(): void
    {
        Notification::fake();

        Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'ABC123',
            'code' => 'ABC123',
        ]);

        Http::fake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'email' => 'google-user.inneru@gmail.com',
                'email_verified' => 'true',
                'name' => 'Google User',
                'picture' => 'https://example.com/avatar.png',
                'aud' => config('services.google.web_client_id'),
                'iss' => 'accounts.google.com',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'google-id-token',
            'create_account' => true,
            'role' => 'coach',
            'company_code' => 'ABC123',
        ]);

        $response->assertCreated()
            ->assertJsonPath('verification_required', true)
            ->assertJsonPath('email', 'google-user.inneru@gmail.com')
            ->assertJsonPath('name', 'Google User');

        $this->assertDatabaseMissing('users', [
            'email' => 'google-user.inneru@gmail.com',
        ]);

        $pending = PendingRegistration::where('email', 'google-user.inneru@gmail.com')->firstOrFail();

        Notification::assertSentTo($pending, PendingRegistrationVerificationNotification::class);

        $this->assertDatabaseHas('pending_registrations', [
            'email' => 'google-user.inneru@gmail.com',
            'name' => 'Google User',
            'role' => 'coach',
            'is_coach' => true,
            'company_code' => 'ABC123',
            'company_name' => 'ABC123',
            'profile_pic' => 'https://example.com/avatar.png',
        ]);
    }

    public function test_google_signup_resolves_a_real_company_id_and_name_instead_of_the_raw_code(): void
    {
        Notification::fake();

        $company = Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
        ]);

        Http::fake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'email' => 'google-company.inneru@gmail.com',
                'email_verified' => 'true',
                'name' => 'Google Company User',
                'picture' => 'https://example.com/avatar.png',
                'aud' => config('services.google.web_client_id'),
                'iss' => 'accounts.google.com',
            ], 200),
        ]);

        $this->postJson('/api/auth/google', [
            'id_token' => 'google-id-token',
            'create_account' => true,
            'role' => 'user',
            'company_code' => ' gen0kus ',
        ])->assertCreated();

        $pending = PendingRegistration::where('email', 'google-company.inneru@gmail.com')->firstOrFail();

        // Regression: company_id/company_name used to be set to the raw
        // code string ("GEN0KUS") instead of the company's real id/name.
        $this->assertSame($company->id, $pending->company_id);
        $this->assertSame($company->id, $pending->active_company_id);
        $this->assertSame('Gencys', $pending->company_name);
        $this->assertSame('Gencys', $pending->active_company_name);
    }

    public function test_google_signup_rejects_an_unknown_company_code(): void
    {
        Http::fake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'email' => 'google-invalid-company.inneru@gmail.com',
                'email_verified' => 'true',
                'name' => 'Google Invalid Company',
                'aud' => config('services.google.web_client_id'),
                'iss' => 'accounts.google.com',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'google-id-token',
            'create_account' => true,
            'role' => 'user',
            'company_code' => 'DOES-NOT-EXIST',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);

        $this->assertDatabaseMissing('pending_registrations', [
            'email' => 'google-invalid-company.inneru@gmail.com',
        ]);
    }

    public function test_google_login_rejects_missing_accounts(): void
    {
        Http::fake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'email' => 'missing-google.inneru@gmail.com',
                'email_verified' => 'true',
                'name' => 'Missing User',
                'aud' => config('services.google.web_client_id'),
                'iss' => 'accounts.google.com',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'google-id-token',
        ]);

        $response->assertNotFound()
            ->assertJsonPath('message', 'User not found. Please create an account first.');

        $this->assertDatabaseMissing('users', [
            'email' => 'missing-google.inneru@gmail.com',
        ]);
    }

    public function test_google_login_reuses_an_existing_user_and_refreshes_profile_data(): void
    {
        $user = User::factory()->create([
            'name' => 'Existing Google User',
            'email' => 'existing-google.inneru@gmail.com',
            'profile_pic' => null,
            'email_verified_at' => now(),
        ]);

        Http::fake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'email' => 'existing-google.inneru@gmail.com',
                'email_verified' => 'true',
                'name' => 'Updated Name',
                'picture' => 'https://example.com/updated-avatar.png',
                'aud' => config('services.google.web_client_id'),
                'iss' => 'https://accounts.google.com',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'google-id-token',
            'create_account' => true,
        ]);

        $response->assertOk()
            ->assertJsonPath('user.email', 'existing-google.inneru@gmail.com');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'email' => 'existing-google.inneru@gmail.com',
            'profile_pic' => 'https://example.com/updated-avatar.png',
        ]);

        $this->assertNotNull($user->fresh()->email_verified_at);
    }

    public function test_apple_signup_creates_a_pending_registration_and_sends_verification_email(): void
    {
        Notification::fake();
        Cache::forget('apple.identity.keys');

        Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'ABC123',
            'code' => 'ABC123',
        ]);

        $rawNonce = bin2hex(random_bytes(16));
        $tokenData = $this->makeAppleIdentityToken([
            'sub' => 'apple-subject-123',
            'email' => 'apple-user.inneru@icloud.com',
            'iss' => 'https://appleid.apple.com',
            'aud' => config('services.apple.bundle_id'),
            'exp' => now()->addHour()->timestamp,
            'iat' => now()->timestamp,
            'nonce' => hash('sha256', $rawNonce),
            'email_verified' => 'true',
        ]);

        Http::fake([
            'https://appleid.apple.com/auth/keys*' => Http::response($tokenData['keys'], 200),
        ]);

        $response = $this->postJson('/api/auth/apple', [
            'identity_token' => $tokenData['token'],
            'raw_nonce' => $rawNonce,
            'create_account' => true,
            'role' => 'coach',
            'company_code' => 'ABC123',
            'email' => 'apple-user.inneru@icloud.com',
            'given_name' => 'Apple',
            'family_name' => 'User',
        ]);

        $response->assertCreated()
            ->assertJsonPath('verification_required', true)
            ->assertJsonPath('email', 'apple-user.inneru@icloud.com')
            ->assertJsonPath('name', 'Apple User');

        $pending = PendingRegistration::where('email', 'apple-user.inneru@icloud.com')->firstOrFail();

        Notification::assertSentTo($pending, PendingRegistrationVerificationNotification::class);

        $this->assertDatabaseHas('pending_registrations', [
            'email' => 'apple-user.inneru@icloud.com',
            'apple_user_id' => 'apple-subject-123',
            'name' => 'Apple User',
            'role' => 'coach',
            'is_coach' => true,
            'company_code' => 'ABC123',
            'company_name' => 'ABC123',
        ]);
    }

    public function test_apple_signup_resolves_a_real_company_id_and_name_instead_of_the_raw_code(): void
    {
        Notification::fake();
        Cache::forget('apple.identity.keys');

        $company = Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
        ]);

        $rawNonce = bin2hex(random_bytes(16));
        $tokenData = $this->makeAppleIdentityToken([
            'sub' => 'apple-subject-company',
            'email' => 'apple-company.inneru@icloud.com',
            'iss' => 'https://appleid.apple.com',
            'aud' => config('services.apple.bundle_id'),
            'exp' => now()->addHour()->timestamp,
            'iat' => now()->timestamp,
            'nonce' => hash('sha256', $rawNonce),
            'email_verified' => 'true',
        ]);

        Http::fake([
            'https://appleid.apple.com/auth/keys*' => Http::response($tokenData['keys'], 200),
        ]);

        $this->postJson('/api/auth/apple', [
            'identity_token' => $tokenData['token'],
            'raw_nonce' => $rawNonce,
            'create_account' => true,
            'role' => 'user',
            'company_code' => ' gen0kus ',
            'email' => 'apple-company.inneru@icloud.com',
            'given_name' => 'Apple',
            'family_name' => 'Company',
        ])->assertCreated();

        $pending = PendingRegistration::where('email', 'apple-company.inneru@icloud.com')->firstOrFail();

        // Regression: company_id/company_name used to be set to the raw
        // code string ("GEN0KUS") instead of the company's real id/name.
        $this->assertSame($company->id, $pending->company_id);
        $this->assertSame($company->id, $pending->active_company_id);
        $this->assertSame('Gencys', $pending->company_name);
        $this->assertSame('Gencys', $pending->active_company_name);
    }

    public function test_apple_signup_rejects_an_inactive_company_code(): void
    {
        Cache::forget('apple.identity.keys');

        Company::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Inactive Company',
            'code' => 'INACTIVE',
            'is_active' => false,
        ]);

        $rawNonce = bin2hex(random_bytes(16));
        $tokenData = $this->makeAppleIdentityToken([
            'sub' => 'apple-subject-inactive-company',
            'email' => 'apple-inactive-company.inneru@icloud.com',
            'iss' => 'https://appleid.apple.com',
            'aud' => config('services.apple.bundle_id'),
            'exp' => now()->addHour()->timestamp,
            'iat' => now()->timestamp,
            'nonce' => hash('sha256', $rawNonce),
            'email_verified' => 'true',
        ]);

        Http::fake([
            'https://appleid.apple.com/auth/keys*' => Http::response($tokenData['keys'], 200),
        ]);

        $response = $this->postJson('/api/auth/apple', [
            'identity_token' => $tokenData['token'],
            'raw_nonce' => $rawNonce,
            'create_account' => true,
            'role' => 'user',
            'company_code' => 'inactive',
            'email' => 'apple-inactive-company.inneru@icloud.com',
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('message', self::INVALID_COMPANY_CODE_MESSAGE)
            ->assertJsonPath('errors.company_code.0', self::INVALID_COMPANY_CODE_MESSAGE);

        $this->assertDatabaseMissing('pending_registrations', [
            'email' => 'apple-inactive-company.inneru@icloud.com',
        ]);
    }

    public function test_apple_login_rejects_missing_accounts(): void
    {
        Cache::forget('apple.identity.keys');

        $rawNonce = bin2hex(random_bytes(16));
        $tokenData = $this->makeAppleIdentityToken([
            'sub' => 'missing-apple-subject',
            'email' => 'missing-apple.inneru@icloud.com',
            'iss' => 'https://appleid.apple.com',
            'aud' => config('services.apple.bundle_id'),
            'exp' => now()->addHour()->timestamp,
            'iat' => now()->timestamp,
            'nonce' => hash('sha256', $rawNonce),
            'email_verified' => 'true',
        ]);

        Http::fake([
            'https://appleid.apple.com/auth/keys*' => Http::response($tokenData['keys'], 200),
        ]);

        $response = $this->postJson('/api/auth/apple', [
            'identity_token' => $tokenData['token'],
            'raw_nonce' => $rawNonce,
        ]);

        $response->assertNotFound()
            ->assertJsonPath('message', 'User not found. Please create an account first.');

        $this->assertDatabaseMissing('users', [
            'email' => 'missing-apple.inneru@icloud.com',
        ]);
    }

    public function test_apple_login_reuses_an_existing_user_and_links_apple_user_id(): void
    {
        Cache::forget('apple.identity.keys');

        $user = User::factory()->create([
            'name' => 'Existing Apple User',
            'email' => 'existing-apple.inneru@icloud.com',
            'apple_user_id' => null,
            'email_verified_at' => now(),
        ]);

        $rawNonce = bin2hex(random_bytes(16));
        $tokenData = $this->makeAppleIdentityToken([
            'sub' => 'apple-subject-existing',
            'email' => 'existing-apple.inneru@icloud.com',
            'iss' => 'https://appleid.apple.com',
            'aud' => config('services.apple.bundle_id'),
            'exp' => now()->addHour()->timestamp,
            'iat' => now()->timestamp,
            'nonce' => hash('sha256', $rawNonce),
            'email_verified' => 'true',
        ]);

        Http::fake([
            'https://appleid.apple.com/auth/keys*' => Http::response($tokenData['keys'], 200),
        ]);

        $response = $this->postJson('/api/auth/apple', [
            'identity_token' => $tokenData['token'],
            'raw_nonce' => $rawNonce,
        ]);

        $response->assertOk()
            ->assertJsonPath('user.email', 'existing-apple.inneru@icloud.com');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'email' => 'existing-apple.inneru@icloud.com',
            'apple_user_id' => 'apple-subject-existing',
        ]);
    }

    /**
     * @param array<string, mixed> $claims
     * @return array{token: string, keys: array<string, array<int, array<string, string>>>}
     */
    private function makeAppleIdentityToken(array $claims, string $kid = 'apple-key-1'): array
    {
        $privateKey = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);

        if ($privateKey === false) {
            throw new \RuntimeException('Unable to create Apple test key pair.');
        }

        $privateKeyPem = '';
        openssl_pkey_export($privateKey, $privateKeyPem);

        $details = openssl_pkey_get_details($privateKey);
        if ($details === false || ! isset($details['rsa'])) {
            throw new \RuntimeException('Unable to extract Apple test public key.');
        }

        $header = $this->base64UrlEncode(json_encode([
            'alg' => 'RS256',
            'kid' => $kid,
            'typ' => 'JWT',
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));

        $payload = $this->base64UrlEncode(json_encode($claims, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));

        $signatureInput = $header.'.'.$payload;
        $signature = '';
        openssl_sign($signatureInput, $signature, $privateKeyPem, OPENSSL_ALGO_SHA256);

        return [
            'token' => $signatureInput.'.'.$this->base64UrlEncode($signature),
            'keys' => [
                'keys' => [
                    [
                        'kty' => 'RSA',
                        'kid' => $kid,
                        'use' => 'sig',
                        'alg' => 'RS256',
                        'n' => $this->base64UrlEncode($details['rsa']['n']),
                        'e' => $this->base64UrlEncode($details['rsa']['e']),
                    ],
                ],
            ],
        ];
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    public static function signupRoleProvider(): array
    {
        return [
            'user' => ['user', false, null, null],
            'coach' => ['coach', true, 'ACME', 'ACME'],
        ];
    }

    public static function loginRoleProvider(): array
    {
        return [
            'user' => ['user', false],
            'coach' => ['coach', true],
        ];
    }
}
