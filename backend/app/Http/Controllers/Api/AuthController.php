<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PendingRegistration;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Symfony\Component\HttpFoundation\Response;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'string', 'email:rfc', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', PasswordRule::min(8)],
            'number' => ['nullable', 'string', 'max:30'],
            'role' => ['required', 'string', 'max:30'],
            'company_code' => ['nullable', 'string', 'max:60'],
            'company_name' => ['nullable', 'string', 'max:120'],
        ]);

        $role = strtolower($validated['role']);
        $companyCode = $validated['company_code'] ?? null;
        $companyName = $validated['company_name'] ?? null;

        $pending = PendingRegistration::updateOrCreate(
            ['email' => $validated['email']],
            [
                'name' => $validated['name'],
                'email' => $validated['email'],
                'number' => $validated['number'] ?? null,
                'role' => $role,
                'is_coach' => $role === 'coach',
                'company_code' => $companyCode,
                'company_name' => $companyName,
                'has_company' => filled($companyCode),
                'company_id' => $companyCode,
                'active_company_id' => $companyCode,
                'active_company_code' => $companyCode,
                'active_company_name' => $companyName,
                'active_company_score_mode' => null,
                'score_mode' => null,
                'company_memberships' => null,
                'company_ids' => null,
                'company_codes' => null,
                'daily_step_goal' => null,
                'daily_tracker_items' => null,
                'profile_pic' => null,
                'birthdate' => null,
                'encrypted_password' => Crypt::encryptString($validated['password']),
            ]
        );

        $verificationEmailSent = $pending->sendVerificationEmail();

        return response()->json([
            'message' => $verificationEmailSent
                ? 'Verification email sent. Please verify your email before signing in.'
                : 'Account created. We could not send the verification email right now, but you can request another one later.',
            'verification_required' => true,
            'verification_email_sent' => $verificationEmailSent,
            'email' => $pending->email,
            'name' => $pending->name,
        ], Response::HTTP_CREATED);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email:rfc'],
            'password' => ['required', 'string'],
        ]);

        if (PendingRegistration::where('email', $validated['email'])->exists()) {
            return response()->json([
                'message' => 'Please verify your email first.',
            ], Response::HTTP_FORBIDDEN);
        }

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'message' => 'The provided credentials are incorrect.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        if ($user->email_verified_at === null) {
            return response()->json([
                'message' => 'Please verify your email first.',
            ], Response::HTTP_FORBIDDEN);
        }

        $user->tokens()->delete();
        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token,
            'user' => $this->userPayload($user),
        ]);
    }

    public function resendVerificationEmail(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email:rfc', 'max:255'],
        ]);

        $user = User::where('email', $validated['email'])->first();
        $pending = PendingRegistration::where('email', $validated['email'])->first();

        if ($user === null) {
            if ($pending !== null) {
                $verificationEmailSent = $pending->sendVerificationEmail();

                return response()->json([
                    'message' => $verificationEmailSent
                        ? 'Verification email sent. Please check your inbox.'
                        : 'We could not send the verification email right now. Please try again later.',
                    'verification_email_sent' => $verificationEmailSent,
                ]);
            }

            return response()->json([
                'message' => 'User not found. Please create an account first.',
            ], Response::HTTP_NOT_FOUND);
        }

        if ($user->hasVerifiedEmail()) {
            return response()->json([
                'message' => 'Your email is already verified.',
            ]);
        }

        $user->sendEmailVerificationNotification();

        return response()->json([
            'message' => 'Verification email sent. Please check your inbox.',
        ]);
    }

    public function google(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'id_token' => ['required', 'string'],
            'create_account' => ['nullable', 'boolean'],
            'role' => ['nullable', 'string', 'max:30'],
            'company_code' => ['nullable', 'string', 'max:60'],
            'company_name' => ['nullable', 'string', 'max:120'],
            'continue_without_company' => ['nullable', 'boolean'],
        ]);

        $response = Http::acceptJson()->get('https://oauth2.googleapis.com/tokeninfo', [
            'id_token' => $validated['id_token'],
        ]);

        if (! $response->successful()) {
            return response()->json([
                'message' => 'Google sign-in failed. Please try again.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $payload = $response->json();
        $email = is_string($payload['email'] ?? null) ? trim($payload['email']) : '';
        $name = is_string($payload['name'] ?? null) ? trim($payload['name']) : '';
        $picture = is_string($payload['picture'] ?? null) ? trim($payload['picture']) : null;
        $issuer = is_string($payload['iss'] ?? null) ? $payload['iss'] : '';
        $audience = is_string($payload['aud'] ?? null) ? $payload['aud'] : '';

        if ($email === '') {
            return response()->json([
                'message' => 'Google account did not return an email address.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        if (! filter_var($payload['email_verified'] ?? false, FILTER_VALIDATE_BOOLEAN)) {
            return response()->json([
                'message' => 'Google account email is not verified.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        if (! in_array($issuer, ['accounts.google.com', 'https://accounts.google.com'], true)) {
            return response()->json([
                'message' => 'Google token issuer is not valid.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        if (! in_array($audience, $this->googleAudienceIds(), true)) {
            return response()->json([
                'message' => 'Google token audience is not recognized.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $user = User::where('email', $email)->first();
        $pending = PendingRegistration::where('email', $email)->first();
        $createAccount = (bool) ($validated['create_account'] ?? false);

        if ($user === null) {
            if ($pending !== null) {
                if (! $createAccount) {
                    return response()->json([
                        'message' => 'Please verify your email first.',
                    ], Response::HTTP_FORBIDDEN);
                }

                $pending->fill([
                    'name' => $name !== '' ? $name : Str::before($email, '@'),
                    'number' => null,
                    'role' => strtolower((string) ($validated['role'] ?? 'user')),
                    'is_coach' => strtolower((string) ($validated['role'] ?? 'user')) === 'coach',
                    'company_code' => $this->resolvedCompanyCode($validated),
                    'company_name' => $this->resolvedCompanyCode($validated),
                    'has_company' => filled($this->resolvedCompanyCode($validated)),
                    'company_id' => $this->resolvedCompanyCode($validated),
                    'active_company_id' => $this->resolvedCompanyCode($validated),
                    'active_company_code' => $this->resolvedCompanyCode($validated),
                    'active_company_name' => $this->resolvedCompanyCode($validated),
                    'profile_pic' => $picture,
                    'encrypted_password' => Crypt::encryptString(Str::random(64)),
                ])->save();

                $verificationEmailSent = $pending->sendVerificationEmail();

                return response()->json([
                    'message' => $verificationEmailSent
                        ? 'Verification email sent. Please verify your email before signing in.'
                        : 'Account created. We could not send the verification email right now, but you can request another one later.',
                    'verification_required' => true,
                    'verification_email_sent' => $verificationEmailSent,
                    'email' => $pending->email,
                    'name' => $pending->name,
                ], Response::HTTP_CREATED);
            }

            if (! $createAccount) {
                return response()->json([
                    'message' => 'User not found. Please create an account first.',
                ], Response::HTTP_NOT_FOUND);
            }

            $role = strtolower((string) ($validated['role'] ?? 'user'));
            $companyCode = $this->resolvedCompanyCode($validated);
            $companyName = $companyCode;
            $displayName = $name !== '' ? $name : Str::before($email, '@');

            $pending = PendingRegistration::create([
                'name' => $displayName,
                'email' => $email,
                'number' => null,
                'role' => $role,
                'is_coach' => $role === 'coach',
                'company_code' => $companyCode,
                'company_name' => $companyName,
                'has_company' => filled($companyCode),
                'company_id' => $companyCode,
                'active_company_id' => $companyCode,
                'active_company_code' => $companyCode,
                'active_company_name' => $companyName,
                'active_company_score_mode' => null,
                'score_mode' => null,
                'company_memberships' => null,
                'company_ids' => null,
                'company_codes' => null,
                'daily_step_goal' => null,
                'daily_tracker_items' => null,
                'birthdate' => null,
                'profile_pic' => $picture,
                'encrypted_password' => Crypt::encryptString(Str::random(64)),
            ]);

            $verificationEmailSent = $pending->sendVerificationEmail();

            return response()->json([
                'message' => $verificationEmailSent
                    ? 'Verification email sent. Please verify your email before signing in.'
                    : 'Account created. We could not send the verification email right now, but you can request another one later.',
                'verification_required' => true,
                'verification_email_sent' => $verificationEmailSent,
                'email' => $pending->email,
                'name' => $pending->name,
            ], Response::HTTP_CREATED);
        }

        if ($user->email_verified_at === null) {
            return response()->json([
                'message' => 'Please verify your email first.',
            ], Response::HTTP_FORBIDDEN);
        }

        $updates = [];

        if (($user->profile_pic === null || $user->profile_pic === '') && filled($picture)) {
            $updates['profile_pic'] = $picture;
        }

        if ($updates !== []) {
            $user->forceFill($updates)->save();
        }

        $user->tokens()->delete();
        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token,
            'user' => $this->userPayload($user),
        ]);
    }

    public function apple(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'identity_token' => ['required', 'string'],
            'raw_nonce' => ['nullable', 'string'],
            'create_account' => ['nullable', 'boolean'],
            'role' => ['nullable', 'string', 'max:30'],
            'company_code' => ['nullable', 'string', 'max:60'],
            'company_name' => ['nullable', 'string', 'max:120'],
            'continue_without_company' => ['nullable', 'boolean'],
            'apple_user_id' => ['nullable', 'string', 'max:255'],
            'email' => ['nullable', 'string', 'email:rfc', 'max:255'],
            'given_name' => ['nullable', 'string', 'max:120'],
            'family_name' => ['nullable', 'string', 'max:120'],
            'full_name' => ['nullable', 'string', 'max:255'],
        ]);

        try {
            $applePayload = $this->verifyAppleIdentityToken(
                $validated['identity_token'],
                is_string($validated['raw_nonce'] ?? null) ? $validated['raw_nonce'] : null,
            );
        } catch (\Throwable) {
            return response()->json([
                'message' => 'Apple sign-in failed. Please try again.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $appleUserId = is_string($applePayload['sub'] ?? null)
            ? trim($applePayload['sub'])
            : trim((string) ($validated['apple_user_id'] ?? ''));
        $email = is_string($applePayload['email'] ?? null)
            ? trim($applePayload['email'])
            : trim((string) ($validated['email'] ?? ''));
        $picture = is_string($applePayload['picture'] ?? null)
            ? trim($applePayload['picture'])
            : null;
        $name = $this->appleDisplayName($validated);
        $createAccount = (bool) ($validated['create_account'] ?? false);
        $supportsAppleUserIdOnUsers = Schema::hasColumn('users', 'apple_user_id');
        $supportsAppleUserIdOnPendingRegistrations = Schema::hasColumn(
            'pending_registrations',
            'apple_user_id'
        );

        if ($appleUserId === '') {
            return response()->json([
                'message' => 'Apple sign-in failed. Please try again.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $user = null;
        if ($supportsAppleUserIdOnUsers) {
            $user = User::where('apple_user_id', $appleUserId)->first();
        }

        if ($user === null && $email !== '') {
            $user = User::where('email', $email)->first();
        }

        $pending = null;
        if ($supportsAppleUserIdOnPendingRegistrations) {
            $pending = PendingRegistration::where('apple_user_id', $appleUserId)->first();
        }

        if ($pending === null && $email !== '') {
            $pending = PendingRegistration::where('email', $email)->first();
        }

        if ($user === null) {
            if ($pending !== null) {
                if (! $createAccount) {
                    return response()->json([
                        'message' => 'Please verify your email first.',
                    ], Response::HTTP_FORBIDDEN);
                }

                $updates = [
                    'name' => $name !== '' ? $name : $pending->name,
                    'profile_pic' => $pending->profile_pic ?? $picture,
                    'encrypted_password' => Crypt::encryptString(Str::random(64)),
                ];

                if ($supportsAppleUserIdOnPendingRegistrations) {
                    $updates['apple_user_id'] = $appleUserId;
                }

                $pending->forceFill($updates)->save();

                $pending->sendVerificationEmail();

                return response()->json([
                    'message' => 'Verification email sent. Please verify your email before signing in.',
                    'verification_required' => true,
                    'email' => $pending->email,
                    'name' => $pending->name,
                ], Response::HTTP_CREATED);
            }

            if (! $createAccount) {
                return response()->json([
                    'message' => 'User not found. Please create an account first.',
                ], Response::HTTP_NOT_FOUND);
            }

            if ($email === '') {
                return response()->json([
                    'message' => 'Apple account did not return an email address.',
                ], Response::HTTP_UNAUTHORIZED);
            }

            $role = strtolower((string) ($validated['role'] ?? 'user'));
            $companyCode = $this->resolvedCompanyCode($validated);
            $companyName = $companyCode;
            $displayName = $name !== '' ? $name : Str::before($email, '@');

            $pendingAttributes = [
                'apple_user_id' => $appleUserId,
                'name' => $displayName,
                'email' => $email,
                'number' => null,
                'role' => $role,
                'is_coach' => $role === 'coach',
                'company_code' => $companyCode,
                'company_name' => $companyName,
                'has_company' => filled($companyCode),
                'company_id' => $companyCode,
                'active_company_id' => $companyCode,
                'active_company_code' => $companyCode,
                'active_company_name' => $companyName,
                'active_company_score_mode' => null,
                'score_mode' => null,
                'company_memberships' => null,
                'company_ids' => null,
                'company_codes' => null,
                'daily_step_goal' => null,
                'daily_tracker_items' => null,
                'birthdate' => null,
                'profile_pic' => $picture,
                'encrypted_password' => Crypt::encryptString(Str::random(64)),
            ];

            if (! $supportsAppleUserIdOnPendingRegistrations) {
                unset($pendingAttributes['apple_user_id']);
            }

            $pending = PendingRegistration::create($pendingAttributes);

            $pending->sendVerificationEmail();

            return response()->json([
                'message' => 'Verification email sent. Please verify your email before signing in.',
                'verification_required' => true,
                'email' => $pending->email,
                'name' => $pending->name,
            ], Response::HTTP_CREATED);
        }

        if ($user->email_verified_at === null) {
            return response()->json([
                'message' => 'Please verify your email first.',
            ], Response::HTTP_FORBIDDEN);
        }

        $updates = [];

        if (
            $supportsAppleUserIdOnUsers
            && ($user->apple_user_id === null || $user->apple_user_id === '')
            && $appleUserId !== ''
        ) {
            $updates['apple_user_id'] = $appleUserId;
        }

        if (($user->profile_pic === null || $user->profile_pic === '') && filled($picture)) {
            $updates['profile_pic'] = $picture;
        }

        if ($updates !== []) {
            $user->forceFill($updates)->save();
        }

        $user->tokens()->delete();
        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token,
            'user' => $this->userPayload($user->refresh()),
        ]);
    }

    public function sendPasswordResetLink(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email:rfc,dns', 'max:255'],
        ]);

        $status = Password::broker()->sendResetLink($validated);

        if ($status !== Password::RESET_LINK_SENT) {
            return response()->json([
                'message' => __($status),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return response()->json([
            'message' => 'Password reset link sent.',
        ]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'string', 'email:rfc', 'max:255'],
            'password' => ['required', 'string', PasswordRule::min(8), 'confirmed'],
        ]);

        $status = Password::reset(
            $validated,
            function (User $user, string $password): void {
                $user->forceFill([
                    'password' => Hash::make($password),
                ])->save();
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            return response()->json([
                'message' => __($status),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return response()->json([
            'message' => 'Password updated successfully.',
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()?->currentAccessToken()?->delete();

        return response()->json([
            'message' => 'Logged out successfully.',
        ]);
    }

    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user === null) {
            return response()->json([
                'message' => 'No authenticated user found.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $user->tokens()->delete();
        $user->delete();

        return response()->json([
            'message' => 'Account deleted successfully.',
        ]);
    }

    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'number' => $user->number,
            'role' => $user->role,
            'is_coach' => (bool) $user->is_coach,
            'company_code' => $user->company_code,
            'company_name' => $user->company_name,
            'companyId' => $user->company_id,
            'companyCode' => $user->company_code,
            'companyName' => $user->company_name,
            'hasCompany' => (bool) $user->has_company,
            'activeCompanyId' => $user->active_company_id,
            'activeCompanyCode' => $user->active_company_code,
            'activeCompanyName' => $user->active_company_name,
            'activeCompanyScoreMode' => $user->active_company_score_mode,
            'scoreMode' => $user->score_mode,
            'companyMemberships' => $user->company_memberships ?? [],
            'companyIds' => $user->company_ids ?? [],
            'companyCodes' => $user->company_codes ?? [],
            'dailyStepGoal' => $user->daily_step_goal,
            'dailyTrackerItems' => $user->daily_tracker_items ?? [],
            'birthdate' => optional($user->birthdate)?->format('Y-m-d'),
            'profile_pic' => $user->profile_pic,
            'created_at' => optional($user->created_at)?->toIso8601String(),
            'updated_at' => optional($user->updated_at)?->toIso8601String(),
        ];
    }

    /**
     * @return array<int, string>
     */
    private function googleAudienceIds(): array
    {
        return array_values(array_filter([
            config('services.google.web_client_id'),
            config('services.google.ios_client_id'),
            config('services.google.android_client_id'),
        ]));
    }

    /**
     * @return array<int, string>
     */
    private function appleAudienceIds(): array
    {
        return array_values(array_filter([
            config('services.apple.bundle_id'),
            config('services.apple.service_id'),
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    private function verifyAppleIdentityToken(string $identityToken, ?string $rawNonce = null): array
    {
        $segments = explode('.', $identityToken);
        if (count($segments) !== 3) {
            throw new \RuntimeException('Invalid Apple identity token.');
        }

        [$encodedHeader, $encodedPayload, $encodedSignature] = $segments;
        $header = json_decode($this->base64UrlDecode($encodedHeader), true);
        $payload = json_decode($this->base64UrlDecode($encodedPayload), true);

        if (! is_array($header) || ! is_array($payload)) {
            throw new \RuntimeException('Invalid Apple identity token payload.');
        }

        if (($header['alg'] ?? null) !== 'RS256') {
            throw new \RuntimeException('Unsupported Apple token algorithm.');
        }

        $kid = is_string($header['kid'] ?? null) ? $header['kid'] : '';
        if ($kid === '') {
            throw new \RuntimeException('Apple token key identifier is missing.');
        }

        $publicKey = $this->applePublicKeyForKid($kid);
        if ($publicKey === null) {
            throw new \RuntimeException('Apple signing key was not found.');
        }

        $signature = $this->base64UrlDecode($encodedSignature);
        $verified = openssl_verify(
            $encodedHeader.'.'.$encodedPayload,
            $signature,
            $publicKey,
            OPENSSL_ALGO_SHA256
        );

        if ($verified !== 1) {
            throw new \RuntimeException('Apple token signature is invalid.');
        }

        if (($payload['iss'] ?? null) !== 'https://appleid.apple.com') {
            throw new \RuntimeException('Apple token issuer is not valid.');
        }

        $audience = is_string($payload['aud'] ?? null) ? $payload['aud'] : '';
        if ($audience === '' || ! in_array($audience, $this->appleAudienceIds(), true)) {
            throw new \RuntimeException('Apple token audience is not recognized.');
        }

        $expiresAt = (int) ($payload['exp'] ?? 0);
        if ($expiresAt < now()->timestamp) {
            throw new \RuntimeException('Apple token has expired.');
        }

        if ($rawNonce !== null && $rawNonce !== '') {
            $expectedNonce = hash('sha256', $rawNonce);
            if (! is_string($payload['nonce'] ?? null) || ! hash_equals($expectedNonce, $payload['nonce'])) {
                throw new \RuntimeException('Apple token nonce is invalid.');
            }
        }

        return $payload;
    }

    private function applePublicKeyForKid(string $kid): ?string
    {
        $keys = Cache::remember('apple.identity.keys', now()->addDay(), function (): array {
            $response = Http::acceptJson()->get('https://appleid.apple.com/auth/keys');
            if (! $response->successful()) {
                return [];
            }

            $payload = $response->json('keys');
            return is_array($payload) ? $payload : [];
        });

        foreach ($keys as $key) {
            if (! is_array($key)) {
                continue;
            }

            if (($key['kid'] ?? null) !== $kid) {
                continue;
            }

            $modulus = is_string($key['n'] ?? null) ? $this->base64UrlDecode($key['n']) : '';
            $exponent = is_string($key['e'] ?? null) ? $this->base64UrlDecode($key['e']) : '';

            if ($modulus === '' || $exponent === '') {
                return null;
            }

            return $this->rsaPublicKeyPem($modulus, $exponent);
        }

        return null;
    }

    private function rsaPublicKeyPem(string $modulus, string $exponent): string
    {
        $modulus = $this->encodeAsn1Integer($modulus);
        $exponent = $this->encodeAsn1Integer($exponent);
        $rsaPublicKey = $this->encodeAsn1Sequence($modulus.$exponent);
        $algorithmIdentifier = $this->encodeAsn1Sequence(
            $this->encodeAsn1ObjectIdentifier('1.2.840.113549.1.1.1').$this->encodeAsn1Null()
        );
        $publicKey = $this->encodeAsn1Sequence(
            $algorithmIdentifier."\x03".$this->encodeLength(strlen($rsaPublicKey) + 1)."\x00".$rsaPublicKey
        );

        return "-----BEGIN PUBLIC KEY-----\n"
            .chunk_split(base64_encode($publicKey), 64, "\n")
            ."-----END PUBLIC KEY-----\n";
    }

    private function encodeAsn1Sequence(string $value): string
    {
        return "\x30".$this->encodeLength(strlen($value)).$value;
    }

    private function encodeAsn1Null(): string
    {
        return "\x05\x00";
    }

    private function encodeAsn1Integer(string $value): string
    {
        if ($value === '') {
            $value = "\x00";
        }

        if ((ord($value[0]) & 0x80) === 0x80) {
            $value = "\x00".$value;
        }

        return "\x02".$this->encodeLength(strlen($value)).$value;
    }

    private function encodeAsn1ObjectIdentifier(string $oid): string
    {
        $parts = array_map('intval', explode('.', $oid));
        $first = array_shift($parts);
        $second = array_shift($parts);

        $encoded = chr(($first * 40) + $second);

        foreach ($parts as $part) {
            $chunks = [];
            do {
                $chunks[] = $part & 0x7f;
                $part >>= 7;
            } while ($part > 0);

            for ($i = count($chunks) - 1; $i >= 0; $i--) {
                $byte = $chunks[$i];
                if ($i !== 0) {
                    $byte |= 0x80;
                }
                $encoded .= chr($byte);
            }
        }

        return "\x06".$this->encodeLength(strlen($encoded)).$encoded;
    }

    private function encodeLength(int $length): string
    {
        if ($length <= 0x7f) {
            return chr($length);
        }

        $temp = '';
        while ($length > 0) {
            $temp = chr($length & 0xff).$temp;
            $length >>= 8;
        }

        return chr(0x80 | strlen($temp)).$temp;
    }

    private function base64UrlDecode(string $value): string
    {
        $remainder = strlen($value) % 4;
        if ($remainder > 0) {
            $value .= str_repeat('=', 4 - $remainder);
        }

        return base64_decode(strtr($value, '-_', '+/')) ?: '';
    }

    /**
     * @param array<string, mixed> $validated
     */
    private function appleDisplayName(array $validated): string
    {
        $fullName = trim((string) ($validated['full_name'] ?? ''));
        if ($fullName !== '') {
            return $fullName;
        }

        $givenName = trim((string) ($validated['given_name'] ?? ''));
        $familyName = trim((string) ($validated['family_name'] ?? ''));

        return trim($givenName.' '.$familyName);
    }

    /**
     * @param array<string, mixed> $validated
     */
    private function resolvedCompanyCode(array $validated): ?string
    {
        $continueWithoutCompany = (bool) ($validated['continue_without_company'] ?? false);
        $companyCode = trim((string) ($validated['company_code'] ?? ''));

        if ($continueWithoutCompany || $companyCode === '') {
            return null;
        }

        return $companyCode;
    }

}
