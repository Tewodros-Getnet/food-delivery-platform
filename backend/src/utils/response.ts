export interface ApiResponse<T = unknown> {
  success: boolean;
  data: T | null;
  error: string | null;
}

export function successResponse<T>(data: T): ApiResponse<T> {
  return { success: true, data, error: null };
}

export function errorResponse(message: string): ApiResponse<null> {
  return { success: false, data: null, error: message };
}
