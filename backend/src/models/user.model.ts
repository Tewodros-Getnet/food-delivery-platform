export type UserRole = 'customer' | 'restaurant' | 'rider' | 'admin';
export type UserStatus = 'active' | 'suspended';
export type UserProvider = 'email' | 'google';

export interface User {
  id: string;
  email: string;
  password_hash: string | null;
  role: UserRole;
  display_name: string | null;
  phone: string | null;
  profile_photo_url: string | null;
  status: UserStatus;
  email_verified: boolean;
  provider: UserProvider;
  external_id: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface PublicUser {
  id: string;
  email: string;
  role: UserRole;
  display_name: string | null;
  phone: string | null;
  profile_photo_url: string | null;
  status: UserStatus;
  provider: UserProvider;
  created_at: Date;
}
