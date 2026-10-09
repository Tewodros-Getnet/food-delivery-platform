// Debug script to check Brevo configuration
require('dotenv').config();

console.log('🔍 Brevo Configuration Debug');
console.log('================================');

console.log('Environment Variables:');
console.log('BREVO_API_KEY exists:', !!process.env.BREVO_API_KEY);
console.log('BREVO_API_KEY length:', process.env.BREVO_API_KEY?.length || 0);
console.log('BREVO_API_KEY starts with "xkeysib":', process.env.BREVO_API_KEY?.startsWith('xkeysib-') || false);
console.log('BREVO_FROM_EMAIL:', process.env.BREVO_FROM_EMAIL);
console.log('BREVO_FROM_NAME:', process.env.BREVO_FROM_NAME);

// Test API key format
const apiKey = process.env.BREVO_API_KEY;
if (apiKey) {
  console.log('\nAPI Key Analysis:');
  console.log('- First 20 chars:', apiKey.substring(0, 20) + '...');
  console.log('- Contains spaces:', apiKey.includes(' '));
  console.log('- Contains quotes:', apiKey.includes('"') || apiKey.includes("'"));
  console.log('- Length check:', apiKey.length > 50 ? '✅ Good length' : '❌ Too short');
}

// Test Brevo API
console.log('\nTesting Brevo API...');
try {
  const Brevo = require('@getbrevo/brevo');
  const apiInstance = new Brevo.TransactionalEmailsApi();
  
  if (apiKey) {
    apiInstance.setApiKey(Brevo.TransactionalEmailsApiApiKeys.apiKey, apiKey);
    
    // Try to get account info (this should fail with 401 if key is wrong)
    apiInstance.getAccount().then((data) => {
      console.log('✅ Brevo API Key is valid!');
      console.log('Account info:', data);
    }).catch((err) => {
      console.log('❌ Brevo API Key validation failed:');
      console.log('Error status:', err.status);
      console.log('Error message:', err.message);
      
      if (err.status === 401) {
        console.log('\n🎯 SOLUTION: Your API key is invalid. Get a new one from:');
        console.log('   https://app.brevo.com/settings/keys/api');
      }
    });
  } else {
    console.log('❌ No API key found in environment variables');
    console.log('\n🎯 SOLUTION: Add BREVO_API_KEY to your environment variables');
  }
} catch (err) {
  console.log('❌ Failed to load Brevo library:', err.message);
}