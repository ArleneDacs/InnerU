# InnerU Laravel Backend

This folder contains the Laravel API that will replace the Firebase data/auth layer for the Flutter app.

## What is wired

- PostgreSQL is the intended production database.
- Laravel Sanctum is installed for mobile API tokens.
- API routes are available under `/api`.
- A basic auth API is included:
  - `POST /api/auth/register`
  - `POST /api/auth/login`
  - `GET /api/me`
  - `POST /api/logout`
  - `GET /api/health`

## Local development

The local `.env` in this workspace is configured for PostgreSQL.

Use these values to connect a local Postgres server:

- host: `127.0.0.1`
- port: `5432`
- database: `inneru`
- username: `postgres`
- password: leave blank unless your local server requires one

If you already have a hosted PostgreSQL database, set `DB_URL` or update the `DB_*` values in `backend/.env`.

After updating the environment, run:

```bash
cd backend
php artisan config:clear
php artisan migrate
```

To inspect the database quickly from Laravel, use:

```bash
cd backend
php artisan tinker
```

Then you can run queries with Eloquent or the `DB` facade.

## Next step

The Flutter app still has many Firebase reads and writes. The backend is now ready, but the client-side migration needs to be done service by service so we do not break the app in one shot.
