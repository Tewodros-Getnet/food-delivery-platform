// Load test environment variables before any tests run
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env.test') });
