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
                <form method="POST" action="{{ url('/password-reset') }}">
                    @csrf
                    <input type="hidden" name="token" value="{{ old('token', $token) }}">
                    <input type="hidden" name="email" value="{{ old('email', $email) }}">

                    <div class="field">
                        <label for="password">New password</label>
                        <input
                            id="password"
                            name="password"
                            type="password"
                            autocomplete="new-password"
                            required
                        >
                    </div>

                    <div class="field">
                        <label for="password_confirmation">Confirm password</label>
                        <input
                            id="password_confirmation"
                            name="password_confirmation"
                            type="password"
                            autocomplete="new-password"
                            required
                        >
                    </div>

                    <div class="actions">
                        <button class="button" type="submit">Save new password</button>
                        <a class="secondary" href="{{ url('/') }}">Back to home</a>
                    </div>
                </form>
            @endif
        @endif
    </main>
</body>
</html>
