import { OAuth2Client } from 'google-auth-library';
import { env } from '../config/env';
import { logger } from '../utils/logger';

const googleClient = new OAuth2Client(env.GOOGLE_CLIENT_ID);

export interface GoogleUserInfo {
  id: string;
  email: string;
  email_verified: boolean;
  name: string | null;
  picture: string | null;
}

/**
 * Verifies a Google ID token and extracts user information
 * @param idToken The Google ID token from the client
 * @returns Promise resolving to verified user info
 * @throws Error if token is invalid or verification fails
 */
export async function verifyGoogleIdToken(idToken: string): Promise<GoogleUserInfo> {
  try {
    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: env.GOOGLE_CLIENT_ID,
    });

    const payload = ticket.getPayload();
    if (!payload) {
      throw new Error('Invalid token payload');
    }

    // Ensure required fields exist
    if (!payload.sub || !payload.email) {
      throw new Error('Missing required user information');
    }

    // Require verified email for security
    if (!payload.email_verified) {
      throw new Error('Google account email must be verified');
    }

    logger.info('Google ID token verified successfully', { 
      userId: payload.sub, 
      email: payload.email 
    });

    return {
      id: payload.sub,
      email: payload.email,
      email_verified: payload.email_verified,
      name: payload.name || null,
      picture: payload.picture || null,
    };
  } catch (err) {
    logger.error('Google ID token verification failed', { 
      error: String(err) 
    });
    throw new Error('Invalid Google ID token');
  }
}