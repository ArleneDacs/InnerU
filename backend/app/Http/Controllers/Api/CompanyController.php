<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Company;
use App\Models\CoachGroup;
use App\Models\CoachRequest;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class CompanyController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $companies = Company::query()
            ->orderBy('name')
            ->get()
            ->map(fn (Company $company) => $this->payload($company));

        return response()->json(['companies' => $companies]);
    }

    public function lookup(Request $request): JsonResponse
    {
        if ($request->user() === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'code' => ['required', 'string', 'max:120'],
        ]);

        $lookup = Str::lower(trim((string) $validated['code']));
        $company = Company::query()
            ->whereRaw('LOWER(code) = ?', [$lookup])
            ->orWhereRaw('LOWER(id) = ?', [$lookup])
            ->first();

        if ($company === null) {
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        return response()->json([
            'company' => $this->payload($company),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:120'],
        ]);

        $name = trim((string) $validated['name']);
        $code = $this->generateUniqueCode($name);
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => $name,
            'code' => $code,
            'is_active' => true,
            'theme_enabled' => false,
            'theme_source' => null,
            'tagline' => null,
            'theme_primary_color' => null,
            'theme_accent_color' => null,
            'theme_background_color' => null,
            'theme_surface_color' => null,
            'theme_ink_color' => null,
            'theme_muted_ink_color' => null,
            'theme_icon_color' => null,
            'theme_mode' => null,
            'theme_is_dark' => false,
        ]);

        return response()->json([
            'company' => $this->payload($company),
        ], Response::HTTP_CREATED);
    }

    public function update(Request $request, Company $company): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:120'],
            'themeEnabled' => ['sometimes', 'boolean'],
            'themeSource' => ['sometimes', 'nullable', 'string', 'max:30'],
            'tagline' => ['sometimes', 'nullable', 'string', 'max:255'],
            'themePrimaryColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeAccentColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeBackgroundColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeSurfaceColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeInkColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeMutedInkColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeIconColor' => ['sometimes', 'nullable', 'string', 'max:32'],
            'themeMode' => ['sometimes', 'nullable', 'string', 'max:20'],
            'themeIsDark' => ['sometimes', 'boolean'],
            'logoUrl' => ['sometimes', 'nullable', 'string', 'max:2048'],
            'logoFileName' => ['sometimes', 'nullable', 'string', 'max:255'],
            'loadingImageUrl' => ['sometimes', 'nullable', 'string', 'max:2048'],
            'loadingImageFileName' => ['sometimes', 'nullable', 'string', 'max:255'],
            'loadingVideoUrl' => ['sometimes', 'nullable', 'string', 'max:2048'],
            'loadingVideoFileName' => ['sometimes', 'nullable', 'string', 'max:255'],
            'clearLoadingImage' => ['sometimes', 'boolean'],
            'clearLoadingVideo' => ['sometimes', 'boolean'],
        ]);

        $originalName = $company->name;
        $originalCode = $company->code;
        $company->fill($this->fillablePayload($validated));
        $company->save();

        if (array_key_exists('name', $validated) && trim((string) $validated['name']) !== $originalName) {
            $this->syncCompanyName(
                companyId: $company->id,
                companyCode: $originalCode,
                companyName: $originalName,
                newName: $company->name,
            );
        }

        return response()->json([
            'company' => $this->payload($company->fresh()),
        ]);
    }

    public function members(Request $request, Company $company): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $users = User::query()
            ->where(function ($query) use ($company): void {
                $query->where('company_id', $company->id)
                    ->orWhere('company_code', $company->code)
                    ->orWhere('company_name', $company->name)
                    ->orWhere('active_company_id', $company->id)
                    ->orWhere('active_company_code', $company->code)
                    ->orWhere('active_company_name', $company->name);
            })
            ->orderBy('name')
            ->get()
            ->map(fn (User $user) => [
                'id' => (string) $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'role' => $user->role,
                'isCoach' => (bool) $user->is_coach,
                'isAdmin' => (bool) $user->is_admin,
                'companyId' => $user->company_id,
                'companyCode' => $user->company_code,
                'companyName' => $user->company_name,
            ]);

        return response()->json(['members' => $users]);
    }

    public function destroy(Request $request, Company $company): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        DB::transaction(function () use ($company): void {
            User::query()
                ->where(function ($query) use ($company): void {
                    $query->where('company_id', $company->id)
                        ->orWhere('company_code', $company->code)
                        ->orWhere('company_name', $company->name)
                        ->orWhere('active_company_id', $company->id)
                        ->orWhere('active_company_code', $company->code)
                        ->orWhere('active_company_name', $company->name);
                })
                ->update([
                    'company_id' => null,
                    'company_code' => null,
                    'company_name' => null,
                    'active_company_id' => null,
                    'active_company_code' => null,
                    'active_company_name' => null,
                    'updated_at' => now(),
                ]);

            CoachGroup::query()
                ->where('company_code', $company->code)
                ->orWhere('company_name', $company->name)
                ->update([
                    'company_code' => null,
                    'company_name' => null,
                    'updated_at' => now(),
                ]);

            CoachRequest::query()
                ->where('company_code', $company->code)
                ->orWhere('company_name', $company->name)
                ->update([
                    'company_code' => null,
                    'company_name' => null,
                    'updated_at' => now(),
                ]);

            $company->delete();
        });

        return response()->json(['message' => 'Deleted.']);
    }

    private function isAdmin(?User $user): bool
    {
        if ($user === null) {
            return false;
        }

        $role = strtolower(trim((string) $user->role));
        return $role === 'admin' || (bool) $user->is_admin;
    }

    private function generateUniqueCode(string $name): string
    {
        $prefix = Str::of($name)
            ->upper()
            ->replaceMatches('/[^A-Z0-9]/', '')
            ->padRight(3, 'X')
            ->substr(0, 3)
            ->toString();

        for ($attempt = 0; $attempt < 20; $attempt++) {
            $suffix = Str::upper(Str::random(4));
            $code = $prefix.$suffix;
            if (! Company::query()->where('code', $code)->exists()) {
                return $code;
            }
        }

        return $prefix.Str::upper(Str::random(4));
    }

    private function fillablePayload(array $validated): array
    {
        $payload = [];
        foreach ([
            'name',
            'themeSource',
            'tagline',
            'themePrimaryColor',
            'themeAccentColor',
            'themeBackgroundColor',
            'themeSurfaceColor',
            'themeInkColor',
            'themeMutedInkColor',
            'themeIconColor',
            'themeMode',
            'logoUrl',
            'logoFileName',
            'loadingImageUrl',
            'loadingImageFileName',
            'loadingVideoUrl',
            'loadingVideoFileName',
        ] as $field) {
            if (array_key_exists($field, $validated)) {
                $payload[$this->snake($field)] = $validated[$field];
            }
        }

        if (array_key_exists('themeEnabled', $validated)) {
            $payload['theme_enabled'] = (bool) $validated['themeEnabled'];
        }
        if (array_key_exists('themeIsDark', $validated)) {
            $payload['theme_is_dark'] = (bool) $validated['themeIsDark'];
        }
        if (array_key_exists('clearLoadingImage', $validated) && $validated['clearLoadingImage']) {
            $payload['loading_image_url'] = null;
            $payload['loading_image_file_name'] = null;
            $payload['loading_image_updated_at'] = null;
        }
        if (array_key_exists('clearLoadingVideo', $validated) && $validated['clearLoadingVideo']) {
            $payload['loading_video_url'] = null;
            $payload['loading_video_file_name'] = null;
            $payload['loading_video_updated_at'] = null;
        }

        return $payload;
    }

    private function snake(string $value): string
    {
        return Str::snake($value);
    }

    private function payload(Company $company): array
    {
        return [
            'id' => $company->id,
            'name' => $company->name,
            'code' => $company->code,
            'isActive' => (bool) $company->is_active,
            'themeEnabled' => (bool) $company->theme_enabled,
            'themeSource' => $company->theme_source,
            'tagline' => $company->tagline,
            'themePrimaryColor' => $company->theme_primary_color,
            'themeAccentColor' => $company->theme_accent_color,
            'themeBackgroundColor' => $company->theme_background_color,
            'themeSurfaceColor' => $company->theme_surface_color,
            'themeInkColor' => $company->theme_ink_color,
            'themeMutedInkColor' => $company->theme_muted_ink_color,
            'themeIconColor' => $company->theme_icon_color,
            'themeMode' => $company->theme_mode,
            'themeIsDark' => (bool) $company->theme_is_dark,
            'logoUrl' => $company->logo_url,
            'logoFileName' => $company->logo_file_name,
            'logoUpdatedAt' => optional($company->logo_updated_at)?->toIso8601String(),
            'loadingImageUrl' => $company->loading_image_url,
            'loadingImageFileName' => $company->loading_image_file_name,
            'loadingImageUpdatedAt' => optional($company->loading_image_updated_at)?->toIso8601String(),
            'loadingVideoUrl' => $company->loading_video_url,
            'loadingVideoFileName' => $company->loading_video_file_name,
            'loadingVideoUpdatedAt' => optional($company->loading_video_updated_at)?->toIso8601String(),
            'createdAt' => optional($company->created_at)?->toIso8601String(),
            'updatedAt' => optional($company->updated_at)?->toIso8601String(),
        ];
    }

    private function syncCompanyName(
        string $companyId,
        string $companyCode,
        string $companyName,
        string $newName,
    ): void {
        User::query()
            ->where(function ($query) use ($companyId, $companyCode, $companyName): void {
                $query->where('company_id', $companyId)
                    ->orWhere('company_code', $companyCode)
                    ->orWhere('company_name', $companyName)
                    ->orWhere('active_company_id', $companyId)
                    ->orWhere('active_company_code', $companyCode)
                    ->orWhere('active_company_name', $companyName);
            })
            ->update([
                'company_name' => $newName,
                'active_company_name' => $newName,
                'updated_at' => now(),
            ]);
    }
}
