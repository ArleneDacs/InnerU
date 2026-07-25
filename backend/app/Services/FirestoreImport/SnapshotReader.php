<?php

namespace App\Services\FirestoreImport;

class SnapshotReader
{
    public function __construct(private readonly string $basePath)
    {
    }

    /** @return array<int, array{id: string, data: array}> */
    public function collection(string $name): array
    {
        return $this->readJsonArray("{$this->basePath}/{$name}.json");
    }

    /** @return array<int, array{id: string, path: string, data: array}> */
    public function collectionGroup(string $name): array
    {
        return $this->readJsonArray("{$this->basePath}/_group_{$name}.json");
    }

    /** @return array<int, array<string, mixed>> */
    public function authUsers(): array
    {
        $path = "{$this->basePath}/auth-users.json";
        if (! file_exists($path)) {
            return [];
        }
        $decoded = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);

        return $decoded['users'] ?? [];
    }

    private function readJsonArray(string $path): array
    {
        if (! file_exists($path)) {
            return [];
        }

        return json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR) ?? [];
    }
}
