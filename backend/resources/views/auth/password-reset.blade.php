<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset your InnerU password</title>
    <style>
        :root {
            color-scheme: light;
            --bg: #eef4f1;
            --card: #ffffff;
            --text: #203630;
            --muted: #5d706c;
            --line: #d6e1dd;
            --accent: #2f7f75;
            --accent-dark: #225d56;
            --danger: #c24a46;
            --danger-bg: #fbecec;
            --success: #1f7a55;
            --success-bg: #ecf8f1;
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 24px;
            background:
                radial-gradient(circle at top, rgba(59, 129, 120, 0.08), transparent 35%),
                linear-gradient(180deg, #f7fbf9 0%, var(--bg) 100%);
            color: var(--text);
            font-family: Arial, Helvetica, sans-serif;
        }

        .card {
            width: min(100%, 560px);
            background: var(--card);
            border-radius: 28px;
            padding: 36px;
            box-shadow: 0 18px 48px rgba(24, 46, 42, 0.12);
            border: 1px solid rgba(47, 127, 117, 0.08);
        }

        .brand {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            min-width: 112px;
            padding: 10px 18px;
            border-radius: 999px;
            background: #e7f4ef;
            color: var(--accent);
            font-size: 13px;
            font-weight: 700;
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }

        h1 {
            margin: 20px 0 12px;
            font-size: 30px;
            line-height: 1.15;
        }

        p {
            margin: 0;
            color: var(--muted);
            line-height: 1.65;
            font-size: 15px;
        }

        .notice {
            margin-top: 18px;
            padding: 14px 16px;
            border-radius: 14px;
            font-size: 14px;
            line-height: 1.6;
        }

        .notice.error {
            color: var(--danger);
            background: var(--danger-bg);
            border: 1px solid rgba(194, 74, 70, 0.18);
        }

        .notice.success {
            color: var(--success);
            background: var(--success-bg);
            border: 1px solid rgba(31, 122, 85, 0.16);
        }

        form {
            margin-top: 24px;
        }

        .field {
            margin-bottom: 16px;
        }

        .input-wrap {
            position: relative;
        }

        label {
            display: block;
            margin-bottom: 8px;
            font-size: 14px;
            font-weight: 700;
            color: var(--text);
        }

        input {
            width: 100%;
            border: 1px solid var(--line);
            border-radius: 14px;
            padding: 14px 15px;
            font-size: 15px;
            font-family: inherit;
            outline: none;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
            background: #fbfdfc;
        }

        .input-wrap input {
            padding-right: 52px;
        }

        .toggle-password {
            position: absolute;
            right: 12px;
            top: 50%;
            transform: translateY(-50%);
            width: 34px;
            height: 34px;
            border: 0;
            border-radius: 999px;
            background: transparent;
            color: #6b7f79;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
        }

        .toggle-password:hover {
            background: rgba(47, 127, 117, 0.08);
            color: var(--accent-dark);
        }

        .toggle-password:focus-visible {
            outline: 2px solid rgba(47, 127, 117, 0.45);
            outline-offset: 2px;
        }

        input:focus {
            border-color: rgba(47, 127, 117, 0.55);
            box-shadow: 0 0 0 4px rgba(47, 127, 117, 0.12);
        }

        .actions {
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
            margin-top: 20px;
        }

        .button {
            appearance: none;
            border: 0;
            border-radius: 999px;
            padding: 14px 22px;
            background: linear-gradient(135deg, #58c6bf 0%, #4aa7a1 100%);
            color: white;
            font-weight: 700;
            font-size: 15px;
            text-decoration: none;
            cursor: pointer;
            box-shadow: 0 12px 28px rgba(74, 167, 161, 0.22);
        }

        .secondary {
            color: var(--accent-dark);
            text-decoration: none;
            font-size: 14px;
            font-weight: 700;
        }

        .helper {
            margin-top: 10px;
            font-size: 13px;
            color: #6f827d;
        }

        .hidden {
            display: none;
        }

        @media (max-width: 520px) {
            .card {
                padding: 28px 20px;
                border-radius: 22px;
            }

            h1 {
                font-size: 26px;
            }
        }
    </style>
</head>
<body>
    <main class="card">
        <div class="brand">InnerU</div>

        @if (!empty($successMessage))
            <h1>Password updated</h1>
            <div class="notice success">{{ $successMessage }}</div>
            <p class="helper">You can close this tab and sign in with your new password.</p>
        @else
            <h1>Reset your password</h1>
            <p>Choose a new password for {{ $email ?: 'your InnerU account' }}.</p>

            @if ($errors->any())
                <div class="notice error">
                    @foreach ($errors->all() as $error)
                        <div>{{ $error }}</div>
                    @endforeach
                </div>
            @endif

            @if (blank($token) || blank($email))
                <div class="notice error">
                    This reset link is incomplete. Please request a new password reset email.
                </div>
            @else
                <form method="POST" action="/password-reset">
                    @csrf
                    <input type="hidden" name="token" value="{{ old('token', $token) }}">
                    <input type="hidden" name="email" value="{{ old('email', $email) }}">

                    <div class="field">
                        <label for="password">New password</label>
                        <div class="input-wrap">
                            <input
                                id="password"
                                name="password"
                                type="password"
                                autocomplete="new-password"
                                required
                            >
                            <button
                                class="toggle-password"
                                type="button"
                                data-toggle-password="password"
                                aria-label="Show password"
                                aria-pressed="false"
                            >
                                <svg data-eye-open xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                                    <path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                    <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.8"/>
                                </svg>
                                <svg data-eye-closed xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="none" viewBox="0 0 24 24" aria-hidden="true" class="hidden">
                                    <path d="M3 3l18 18" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                                    <path d="M10.6 10.6a2.5 2.5 0 0 0 3.53 3.53" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                                    <path d="M6.2 6.2C4 7.8 2.6 10 2 12c.9 3.2 4.6 6.5 10 6.5 1.9 0 3.7-.4 5.2-1.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                    <path d="M17.8 17.8C20 16.2 21.4 14 22 12c-.9-3.2-4.6-6.5-10-6.5-1.3 0-2.5.2-3.6.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>
                            </button>
                        </div>
                    </div>

                    <div class="field">
                        <label for="password_confirmation">Confirm password</label>
                        <div class="input-wrap">
                            <input
                                id="password_confirmation"
                                name="password_confirmation"
                                type="password"
                                autocomplete="new-password"
                                required
                            >
                            <button
                                class="toggle-password"
                                type="button"
                                data-toggle-password="password_confirmation"
                                aria-label="Show confirm password"
                                aria-pressed="false"
                            >
                                <svg data-eye-open xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                                    <path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                    <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.8"/>
                                </svg>
                                <svg data-eye-closed xmlns="http://www.w3.org/2000/svg" width="18" height="18" fill="none" viewBox="0 0 24 24" aria-hidden="true" class="hidden">
                                    <path d="M3 3l18 18" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                                    <path d="M10.6 10.6a2.5 2.5 0 0 0 3.53 3.53" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                                    <path d="M6.2 6.2C4 7.8 2.6 10 2 12c.9 3.2 4.6 6.5 10 6.5 1.9 0 3.7-.4 5.2-1.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                    <path d="M17.8 17.8C20 16.2 21.4 14 22 12c-.9-3.2-4.6-6.5-10-6.5-1.3 0-2.5.2-3.6.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
                                </svg>
                            </button>
                        </div>
                    </div>

                    <div class="actions">
                        <button class="button" type="submit">Save new password</button>
                        <a class="secondary" href="{{ url('/') }}">Back to home</a>
                    </div>
                </form>
            @endif
        @endif
    </main>
    <script>
        document.querySelectorAll('[data-toggle-password]').forEach((button) => {
            const targetId = button.getAttribute('data-toggle-password');
            const input = targetId ? document.getElementById(targetId) : null;
            const eyeOpen = button.querySelector('[data-eye-open]');
            const eyeClosed = button.querySelector('[data-eye-closed]');

            if (!input || !eyeOpen || !eyeClosed) return;

            button.addEventListener('click', () => {
                const isHidden = input.type === 'password';
                input.type = isHidden ? 'text' : 'password';
                eyeOpen.classList.toggle('hidden', !isHidden);
                eyeClosed.classList.toggle('hidden', isHidden);
                button.setAttribute('aria-pressed', String(isHidden));
                button.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
            });
        });
    </script>
</body>
</html>
