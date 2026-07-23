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

## Mail delivery

The signup flow sends a verification email after account creation.

- For local development, keep `MAIL_MAILER=log` so signup never depends on SMTP.
- For production SMTP with Brevo, set:

```env
MAIL_MAILER=smtp
MAIL_SCHEME=tls
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=your-brevo-smtp-login
MAIL_PASSWORD=your-brevo-smtp-key
MAIL_TIMEOUT=10
```

- Brevo recommends using your SMTP login email as the username and your SMTP key as the password.
- Brevo supports ports `587`, `465`, and `2525`; `587` with `tls` is the default choice.
- If you use queued mail notifications, run a queue worker in production:

```bash
php artisan queue:work --tries=1 --timeout=90
```

- Make sure the sender address in `MAIL_FROM_ADDRESS` is an authenticated Brevo sender or a verified domain.

## Next step

The Flutter app still has many Firebase reads and writes. The backend is now ready, but the client-side migration needs to be done service by service so we do not break the app in one shot.
