<?php

namespace Tests\Feature;

use App\Models\PendingRegistration;
use App\Models\User;
use App\Notifications\PendingRegistrationVerificationNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    #[DataProvider('signupRoleProvider')]
    public function test_register_stores_a_pending_registration_for_each_role(
        string $role,
        bool $isCoach,
        ?string $companyCode,
        ?string $companyName
    ): void {
        Notification::fake();

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

    public function test_password_reset_web_route_redirects_to_the_flutter_app(): void
    {
        $response = $this->get('/password-reset?mode=resetPassword&token=abc123&email=user%40example.com');

        $redirectUrl = $response->headers->get('Location');

        $this->assertNotNull($redirectUrl);
        $this->assertStringStartsWith(
            rtrim((string) config('app.frontend_url'), '/').'/password-reset',
            $redirectUrl
        );

        parse_str(parse_url($redirectUrl, PHP_URL_QUERY) ?? '', $query);
        $this->assertSame('resetPassword', $query['mode'] ?? null);
        $this->assertSame('abc123', $query['token'] ?? null);
        $this->assertSame('user@example.com', $query['email'] ?? null);
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
