export interface ModifierOption {
  name: string;
  price: number; // additional price (0 = no extra charge)
}

export interface ModifierGroup {
  name: string;
  type: 'single' | 'multi'; // single = radio, multi = checkboxes
  required: boolean;
  options: ModifierOption[];
}

export interface MenuItem {
  id: string;
  restaurant_id: string;
  name: string;
  description: string | null;
  price: number;
  category: string | null;
  image_url: string;
  available: boolean;
  modifiers: ModifierGroup[];
  created_at: Date;
  updated_at: Date;
}
