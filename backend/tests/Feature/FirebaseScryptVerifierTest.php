<?php
// backend/tests/Feature/FirebaseScryptVerifierTest.php

namespace Tests\Feature;

use App\Services\FirebaseScryptVerifier;
use Tests\TestCase;

class FirebaseScryptVerifierTest extends TestCase
{
    private string $fakeVerifierPath;
    private string $fakeConfigPath;

    protected function setUp(): void
    {
        parent::setUp();

        // A stand-in for verify.js that matches on a fixed password without touching real crypto.
        $this->fakeVerifierPath = sys_get_temp_dir().'/fake-verify-'.uniqid().'.js';
        file_put_contents($this->fakeVerifierPath, <<<'JS'
            let data = '';
            process.stdin.on('data', (c) => { data += c; });
            process.stdin.on('end', () => {
                const input = JSON.parse(data);
                if (input.password === 'correct-password' && input.hash === 'known-hash' && input.salt === 'known-salt') {
                    process.stdout.write('MATCH');
                    process.exit(0);
                }
                process.stdout.write('NOMATCH');
                process.exit(1);
            });
            JS);

        $this->fakeConfigPath = sys_get_temp_dir().'/fake-hash-config-'.uniqid().'.json';
        file_put_contents($this->fakeConfigPath, json_encode(['signerKey' => 'x', 'saltSeparator' => 'y', 'rounds' => 8, 'memCost' => 14]));
    }

    protected function tearDown(): void
    {
        @unlink($this->fakeVerifierPath);
        @unlink($this->fakeConfigPath);
        parent::tearDown();
    }

    public function test_verify_returns_true_when_the_node_script_reports_a_match(): void
    {
        $verifier = new FirebaseScryptVerifier($this->fakeVerifierPath, $this->fakeConfigPath);

        $this->assertTrue($verifier->verify('correct-password', 'known-hash', 'known-salt'));
    }

    public function test_verify_returns_false_when_the_node_script_reports_no_match(): void
    {
        $verifier = new FirebaseScryptVerifier($this->fakeVerifierPath, $this->fakeConfigPath);

        $this->assertFalse($verifier->verify('wrong-password', 'known-hash', 'known-salt'));
    }
}
