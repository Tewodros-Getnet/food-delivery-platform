export type RestaurantStatus = 'pending' | 'approved' | 'rejected' | 'suspended';

export interface Restaurant {
  id: string;
  owner_id: string;
  name: string;
  description: string | null;
  logo_url: string | null;
  cover_image_url: string | null;
  address: string;
  latitude: number;
  longitude: number;
  category: string | null;
  status: RestaurantStatus;
  average_rating: number;
  is_open?: boolean;
  operating_hours?: Record<string, { open: string; close: string }> | null;
  minimum_order_value?: number;
  promo_banner_text?: string | null;
  promo_banner_image_url?: string | null;
  created_at: Date;
  updated_at: Date;
}
