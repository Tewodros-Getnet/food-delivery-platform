export interface MenuItem {
  id: string;
  restaurant_id: string;
  name: string;
  description: string | null;
  price: number;
  category: string | null;
  image_url: string;
  available: boolean;
  created_at: Date;
  updated_at: Date;
}
