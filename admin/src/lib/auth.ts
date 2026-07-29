import axios from 'axios';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000/api/v1';

export async function login(email: string, password: string) {
  const res = await axios.post(`${API_URL}/auth/login`, { email, password });
  const { tokens, user } = res.data.data as { tokens: { jwt: string; refreshToken: string }; user: { role: string } };
  if (user.role !== 'admin') throw new Error('Access denied: admin only');
  localStorage.setItem('jwt', tokens.jwt);
  localStorage.setItem('refreshToken', tokens.refreshToken);
  return user;
}

export function logout() {
  localStorage.clear();
  window.location.href = '/login';
}

export function isAuthenticated(): boolean {
  if (typeof window === 'undefined') return false;
  return !!localStorage.getItem('jwt');
}
