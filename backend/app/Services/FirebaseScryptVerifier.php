<?php
// backend/app/Services/FirebaseScryptVerifier.php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Symfony\Component\Process\Exception\ExceptionInterface;
use Symfony\Component\Process\Process;

class FirebaseScryptVerifier
{
    public function __construct(
        private readonly string $nodeVerifierPath,
        private readonly string $hashConfigPath,
    ) {
    }

    public function verify(string $plainPassword, string $base64Hash, string $base64Salt): bool
    {
        $process = new Process(['node', $this->nodeVerifierPath, $this->hashConfigPath]);
        $process->setInput(json_encode([
            'password' => $plainPassword,
            'hash' => $base64Hash,
            'salt' => $base64Salt,
        ], JSON_THROW_ON_ERROR));

        try {
            $process->run();
        } catch (ExceptionInterface $exception) {
            Log::error('FirebaseScryptVerifier failed to run the node verifier process.', [
                'exception' => $exception,
            ]);

            return false;
        }

        return $process->getExitCode() === 0;
    }
}
