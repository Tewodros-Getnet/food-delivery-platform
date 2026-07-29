export type OrderStatus =
  | 'pending_payment'
  | 'payment_failed'
  | 'pending_acceptance'
  | 'confirmed'
  | 'ready_for_pickup'
  | 'rider_assigned'
  | 'picked_up'
  | 'delivered'
  | 'cancelled';

export interface Order {
  id: string;
  customer_id: string;
  restaurant_id: string;
  rider_id: string | null;
  delivery_address_id: string;
  status: OrderStatus;
  subtotal: number;
  delivery_fee: number;
  total: number;
  payment_reference: string | null;
  payment_status: string | null;
  cancellation_reason: string | null;
  cancelled_at: Date | null;
  cancelled_by: 'customer' | 'restaurant' | 'admin' | 'system' | null;
  acceptance_deadline: Date | null;
  estimated_prep_time_minutes: number | null;
  notes?: string | null;
  estimated_delivery_time?: Date | null;
  payment_method?: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface OrderItem {
  id: string;
  order_id: string;
  menu_item_id: string;
  quantity: number;
  unit_price: number;
  item_name: string;
  item_image_url: string | null;
}

export interface CartItem {
  menuItemId: string;
  quantity: number;
}
