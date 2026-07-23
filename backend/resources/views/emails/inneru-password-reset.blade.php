<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset your InnerU password</title>
</head>
<body style="margin:0;padding:0;background:#eef6f2;font-family:Arial,Helvetica,sans-serif;color:#21423c;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:linear-gradient(180deg,#f4faf7 0%,#e6f2ed 100%);padding:40px 16px;">
        <tr>
            <td align="center">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:640px;background:#ffffff;border-radius:28px;overflow:hidden;box-shadow:0 18px 50px rgba(33,66,60,0.12);">
                    <tr>
                        <td style="padding:42px 42px 24px;text-align:center;background:linear-gradient(135deg,#ffffff 0%,#f7fcfa 100%);">
                            @if (!empty($logoPath) && is_file($logoPath))
                                <img
                                    src="{{ $message->embed($logoPath) }}"
                                    alt="InnerU"
                                    width="110"
                                    height="110"
                                    style="display:block;margin:0 auto 18px;max-width:110px;width:110px;height:110px;object-fit:contain;border-radius:28px;"
                                >
                            @else
                                <div style="display:inline-block;padding:10px 18px;border-radius:999px;background:#e7f4ef;color:#2f7f75;font-size:13px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;">
                                    InnerU
                                </div>
                            @endif
                            <h1 style="margin:22px 0 12px;font-size:30px;line-height:1.15;color:#173530;">Reset your password</h1>
                            <p style="margin:0 auto;max-width:480px;font-size:16px;line-height:1.7;color:#57726c;">
                                Hi, we received a request to reset the password for {{ $email }}. Tap the button below to create a new password for your InnerU account.
                            </p>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:8px 42px 10px;text-align:center;">
                            <a href="{{ $actionUrl }}" style="display:inline-block;padding:16px 34px;background:linear-gradient(135deg,#58c6bf 0%,#4aa7a1 100%);color:#ffffff;text-decoration:none;font-size:16px;font-weight:700;border-radius:999px;box-shadow:0 12px 28px rgba(74,167,161,0.28);">
                                Reset Password
                            </a>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:14px 42px 12px;text-align:center;">
                            <p style="margin:0;font-size:14px;line-height:1.7;color:#6b827d;">
                                If the button does not work, copy and paste this link into your browser:
                            </p>
                            <p style="word-break:break-all;margin:10px 0 0;font-size:13px;line-height:1.7;color:#2f7f75;">
                                {{ $actionUrl }}
                            </p>
                        </td>
                    </tr>
                    <tr>
                        <td style="padding:18px 42px 42px;text-align:center;">
                            <p style="margin:0;font-size:13px;line-height:1.7;color:#7b8f8a;">
                                If you did not request this password reset, you can safely ignore this email.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
