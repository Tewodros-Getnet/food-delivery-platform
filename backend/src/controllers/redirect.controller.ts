import { Request, Response } from 'express';

// Simple redirect controller for password reset links
export function redirectToApp(req: Request, res: Response) {
  const { app, token } = req.query;
  
  if (!token || !app) {
    return res.status(400).send('Invalid redirect parameters');
  }

  // Try to open the app with deep link
  const deepLink = `fooddelivery://${app}/reset-password?token=${token}`;
  
  // Create HTML page that tries deep link first, then shows manual instructions
  const html = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Open Tana Delivery App</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { 
            background: white; 
            padding: 30px; 
            border-radius: 15px; 
            text-align: center; 
            max-width: 400px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .icon { 
            width: 60px; 
            height: 60px; 
            background: #f97316; 
            border-radius: 50%; 
            margin: 0 auto 20px; 
            display: flex; 
            align-items: center; 
            justify-content: center;
            color: white;
            font-size: 24px;
        }
        h1 { color: #1f2937; margin: 0 0 10px; font-size: 24px; }
        p { color: #6b7280; line-height: 1.5; margin: 0 0 20px; }
        .btn { 
            background: #f97316; 
            color: white; 
            padding: 15px 25px; 
            border: none; 
            border-radius: 8px; 
            font-size: 16px; 
            font-weight: 600; 
            cursor: pointer; 
            text-decoration: none; 
            display: inline-block;
            margin: 10px;
        }
        .btn:hover { background: #ea580c; }
        .instructions { 
            background: #f3f4f6; 
            padding: 15px; 
            border-radius: 8px; 
            margin-top: 20px; 
            text-align: left; 
        }
        .instructions h3 { margin-top: 0; color: #1f2937; }
        .instructions ol { margin: 10px 0; padding-left: 20px; }
        .instructions li { margin: 5px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🔑</div>
        <h1>Reset Your Password</h1>
        <p>Click the button below to open the Tana Delivery app and reset your password.</p>
        
        <a href="${deepLink}" class="btn" onclick="setTimeout(() => showInstructions(), 2000);">
            Open Tana Delivery App
        </a>
        
        <div id="instructions" class="instructions" style="display: none;">
            <h3>App didn't open?</h3>
            <ol>
                <li>Make sure you have the Tana Delivery app installed</li>
                <li>Copy this token: <strong>${token}</strong></li>
                <li>Open the app manually</li>
                <li>Go to "Forgot Password?" and enter the token</li>
            </ol>
        </div>
    </div>
    
    <script>
        function showInstructions() {
            document.getElementById('instructions').style.display = 'block';
        }
        
        // Auto-try deep link on page load
        setTimeout(() => {
            window.location.href = '${deepLink}';
        }, 1000);
        
        // Show instructions after 3 seconds
        setTimeout(showInstructions, 3000);
    </script>
</body>
</html>
  `;
  
  res.send(html);
}