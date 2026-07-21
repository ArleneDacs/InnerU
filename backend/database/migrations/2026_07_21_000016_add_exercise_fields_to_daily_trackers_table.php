<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Exercise fields are part of the base table schema now.
    }

    public function down(): void
    {
        // No-op.
    }
};
