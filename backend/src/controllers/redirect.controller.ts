import { Request, Response } from 'express';

export function redirectToApp(req: Request, res: Response) {
  const { app, token } = req.query;

  if (!token || !app) {
    return res.status(400).send('Invalid link — missing parameters.');
  }

  const deepLink = `fooddelivery://${app}/reset-password?token=${token}`;

  // Use a meta-refresh as the primary trigger (works even without JS)
  // plus JS window.location for speed. The <a> is the manual fallback.
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Opening Tana Delivery…</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         background:#fff8f0;min-height:100vh;display:flex;
         align-items:center;justify-content:center;padding:24px}
    .card{background:#fff;border-radius:20px;padding:36px 28px;
          max-width:380px;width:100%;text-align:center;
          box-shadow:0 4px 24px rgba(0,0,0,.08)}
    .icon{font-size:48px;margin-bottom:16px}
    h1{font-size:20px;font-weight:700;color:#111827;margin-bottom:8px}
    p{font-size:14px;color:#6b7280;line-height:1.6;margin-bottom:24px}
    .btn{display:inline-block;background:#f97316;color:#fff;
         font-size:15px;font-weight:600;padding:14px 32px;
         border-radius:12px;text-decoration:none;width:100%}
    .btn:active{background:#ea580c}
    .note{font-size:12px;color:#9ca3af;margin-top:16px}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">🔑</div>
    <h1>Reset Your Password</h1>
    <p id="msg">Opening the Tana Delivery app…</p>
    <a href="${deepLink}" class="btn" id="btn">Open in App</a>
    <p class="note">Link expires 30 minutes after it was sent.</p>
  </div>
  <script>
    // Fire immediately
    window.location.href = "${deepLink}";
    // Update message after 2.5 s if browser is still open
    setTimeout(function(){
      document.getElementById('msg').textContent =
        "If the app didn't open, tap the button below. Make sure the Tana Delivery app is installed.";
    }, 2500);
  </script>
</body>
</html>`;

  res.send(html);
}
