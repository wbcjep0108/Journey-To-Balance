/* eslint-disable max-len -- email markup needs complete inline CSS declarations */

/** Builds the branded HTML email used for PIN reset codes. */
export function buildPinResetEmailHtml(otp: string): string {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <title>Journey to Balance PIN reset code</title>
  </head>
  <body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#121212;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Use ${otp} to reset your Journey to Balance PIN. This code expires in 10 minutes.</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#f3f4f6;">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:560px;background-color:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,0.08);">
            <tr>
              <td style="padding:24px 32px;background-color:#121212;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                  <tr>
                    <td style="width:42px;height:42px;border-radius:21px;background-color:#ffffff;text-align:center;vertical-align:middle;font-size:14px;font-weight:800;color:#121212;">JB</td>
                    <td style="padding-left:12px;font-size:18px;font-weight:700;color:#ffffff;">Journey to Balance</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:40px 32px 32px;">
                <div style="font-size:12px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#6b7280;">PIN security</div>
                <h1 style="margin:10px 0 12px;font-size:28px;line-height:1.2;color:#121212;">Reset your PIN</h1>
                <p style="margin:0;font-size:16px;line-height:1.6;color:#4b5563;">Enter this verification code in Journey to Balance to continue resetting your PIN.</p>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:28px 0 20px;width:100%;">
                  <tr>
                    <td align="center" style="padding:24px;background-color:#f3f4f6;border:1px solid #e5e7eb;border-radius:18px;">
                      <div style="font-size:12px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:#6b7280;">Your verification code</div>
                      <div style="margin-top:10px;font-size:40px;line-height:1;font-weight:800;letter-spacing:12px;color:#121212;">${otp}</div>
                    </td>
                  </tr>
                </table>
                <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:0 auto 26px;">
                  <tr>
                    <td style="padding:8px 14px;border-radius:999px;background-color:#121212;font-size:13px;font-weight:700;color:#ffffff;">&#9201;&nbsp; Expires in 10 minutes</td>
                  </tr>
                </table>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;">
                  <tr>
                    <td style="padding:16px;border-left:4px solid #121212;background-color:#f9fafb;font-size:13px;line-height:1.55;color:#4b5563;">
                      <strong style="color:#121212;">Keep this code private.</strong><br>
                      Journey to Balance will never ask you to share this code. If you did not request a PIN reset, you can safely ignore this email.
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:20px 32px;border-top:1px solid #e5e7eb;background-color:#fafafa;font-size:12px;line-height:1.5;color:#6b7280;">
                This automated message was sent by Journey to Balance.<br>
                Please do not reply to this email.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}
