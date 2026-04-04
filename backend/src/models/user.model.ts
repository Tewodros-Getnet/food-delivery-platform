export type UserRole = 'customer' | 'restaurant' | 'rider' | 'admin';
export type UserStatus = 'active' | 'suspended';

export interface User {
  id: string;
  email: string;
  password_hash: string;
  role: UserRole;
  display_name: string | null;
  phone: string | null;
  profile_photo_url: string | null;
  status: UserStatus;
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
  created_at: Date;
}
