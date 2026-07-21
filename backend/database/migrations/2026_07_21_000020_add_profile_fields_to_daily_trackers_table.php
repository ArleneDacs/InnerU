<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Profile tracker fields are already included in the base schema.
    }

    public function down(): void
    {
        // No-op.
    }
};
