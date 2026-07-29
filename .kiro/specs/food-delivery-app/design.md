# Design Document

## Overview

The food delivery platform is a multi-tenant system connecting customers, restaurants, riders, and administrators through a centralized Node.js + Express REST API backed by PostgreSQL. The architecture follows a hub-and-spoke model where the backend acts as the authoritative source of truth and event coordinator, while four distinct client applications (three Flutter mobile apps and one Next.js web dashboard) provide role-specific interfaces.

The system handles the complete order lifecycle: from menu browsing and cart management through payment processing, restaurant preparation, rider dispatch, real-time delivery tracking, and post-delivery reviews. Real-time communication is achieved through WebSocket connections for order status updates and rider location broadcasts. Payment processing integrates with Chapa's payment gateway, while media assets are stored on Cloudinary. Push notifications are delivered via Firebase Cloud Messaging (FCM).

Key design principles:
- **Single source of truth**: All state transitions occur in the backend
- **Event-driven coordination**: WebSocket broadcasts keep all clients synchronized
- **Role-based access control**: JWT tokens encode user roles; middleware enforces endpoint permissions
- **Idempotent operations**: Payment webhooks and critical state transitions are designed to handle duplicate events safely
- **Graceful degradation**: Location tracking and real-time updates degrade gracefully when connectivity is poor

---

## Architecture

### System Components

```mermaid
graph TB
    subgraph Clients
        CA[Customer App<br/>Flutter]
        RA[Restaurant App<br/>Flutter]
        RDA[Rider App<br/>Flutter]
        AD[Admin Dashboard<br/>Next.js]
    end
    
    subgraph Backend
        API[Express REST API<br/>Node.js]
        WS[WebSocket Server<br/>Socket.io]
        AUTH[Auth Middleware<br/>JWT + RBAC]
    end
    
    subgraph Data
        DB[(PostgreSQL)]
    end
    
    subgraph External
        CHAPA[Chapa Payment<br/>Gateway]
        CLOUD[Cloudinary<br/>Image Storage]
        FCM[Firebase Cloud<br/>Messaging]
        MAPS[Mapbox API]
    end
    
    CA -->|HTTP + WS| API
    RA -->|HTTP + WS| API
    RDA -->|HTTP + WS| API
    AD -->|HTTP + WS| API
    
    API --> AUTH
    API --> WS
    API --> DB
    
    API -->|Payment Init| CHAPA
    CHAPA -->|Webhook| API
    
    API -->|Upload| CLOUD
    API -->|Push Notifications| FCM
    
    CA -->|Geocoding| MAPS
    RDA -->|Navigation| MAPS
```

### Technology Stack

**Backend:**
- Runtime: Node.js (LTS version)
- Framework: Express.js
- Database: PostgreSQL (hosted on Supabase)
- Real-time: Socket.io (WebSocket library)
- Authentication: jsonwebtoken + bcrypt
- ORM/Query Builder: pg (node-postgres)
- Validation: express-validator or Zod
- Deployment: Render

**Mobile Apps (Customer, Restaurant, Rider) — 3 separate Flutter apps:**
- Framework: Flutter 3.x
- HTTP Client: Dio
- State Management: Riverpod
- Secure Storage: flutter_secure_storage
- WebSocket: socket_io_client
- Maps: flutter_map + OpenStreetMap (no API key required)
- Push Notifications: firebase_messaging

**Admin Dashboard:**
- Framework: Next.js 14+ (App Router)
- UI Library: React 18+
- HTTP Client: fetch API or axios
- WebSocket: socket.io-client
- Styling: Tailwind CSS
- Deployment: Vercel

**External Services:**
- Payment Gateway: Chapa
- Image Storage: Cloudinary
- Push Notifications: Firebase Cloud Messaging (FCM)
- Maps & Geocoding: OpenStreetMap (via flutter_map, free, no API key)

### Deployment Architecture

```mermaid
graph LR
    subgraph Render
        API[Express API<br/>Container]
    end

    subgraph Supabase
        DB[(PostgreSQL<br/>Managed DB)]
    end

    subgraph Vercel
        ADMIN[Next.js Admin<br/>Dashboard]
    end
    
    subgraph Mobile
        FLUTTER[3 Flutter Apps<br/>App Store + Play Store]
    end
    
    API --> DB
    FLUTTER -->|HTTPS| API
    ADMIN -->|HTTPS| API
    
    API -->|Webhook| CHAPA[Chapa]
    API -->|Upload| CLOUD[Cloudinary]
    API -->|FCM| FCM[Firebase]
```

---

## Components and Interfaces

### Backend API Structure

The backend is organized into the following modules:

**1. Authentication Module**
- Endpoints: `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`
- Responsibilities: User registration, login, JWT issuance, refresh token management, logout
- Dependencies: bcrypt for password hashing, jsonwebtoken for JWT generation

**2. User Management Module**
- Endpoints: `GET /users/profile`, `PUT /users/profile`, `PUT /users/password`, `POST /users/addresses`
- Responsibilities: Profile updates, password changes, address management
- Dependencies: Cloudinary SDK for profile photo uploads

**3. Restaurant Module**
- Endpoints: `POST /restaurants`, `GET /restaurants`, `GET /restaurants/:id`, `PUT /restaurants/:id`, `POST /restaurants/:id/approve` (admin only)
- Responsibilities: Restaurant registration, listing, approval workflow, suspension
- Dependencies: Cloudinary SDK for logo/cover image uploads

**4. Menu Module**
- Endpoints: `POST /restaurants/:id/menu`, `GET /restaurants/:id/menu`, `PUT /menu/:id`, `DELETE /menu/:id`
- Responsibilities: Menu item CRUD, availability toggling, category management
- Dependencies: Cloudinary SDK for menu item images

**5. Order Module**
- Endpoints: `POST /orders`, `GET /orders`, `GET /orders/:id`, `PUT /orders/:id/cancel`, `PUT /orders/:id/status`
- Responsibilities: Order creation, payment initiation, status transitions, cancellation
- Dependencies: Chapa SDK, WebSocket server for status broadcasts

**6. Payment Module**
- Endpoints: `POST /payments/webhook` (Chapa webhook handler), `POST /payments/refund`
- Responsibilities: Payment confirmation, webhook signature verification, refund processing
- Dependencies: Chapa SDK, idempotency key storage

**7. Rider Module**
- Endpoints: `GET /riders/available`, `PUT /riders/location`, `PUT /riders/availability`, `POST /riders/:id/assign`
- Responsibilities: Rider location tracking, availability management, dispatch logic
- Dependencies: Geospatial distance calculation (PostGIS or Haversine formula)

**8. Delivery Module**
- Endpoints: `POST /deliveries/:id/accept`, `POST /deliveries/:id/decline`, `PUT /deliveries/:id/pickup`, `PUT /deliveries/:id/deliver`
- Responsibilities: Delivery request handling, pickup confirmation, delivery completion
- Dependencies: WebSocket server for real-time notifications

**9. Rating Module**
- Endpoints: `POST /orders/:id/rate`, `GET /restaurants/:id/ratings`, `GET /riders/:id/ratings`
- Responsibilities: Rating submission, average rating calculation, rating retrieval
- Dependencies: PostgreSQL aggregate functions

**10. Admin Module**
- Endpoints: `GET /admin/restaurants`, `GET /admin/users`, `GET /admin/disputes`, `GET /admin/analytics`, `PUT /admin/users/:id/suspend`
- Responsibilities: Platform oversight, dispute resolution, analytics aggregation
- Dependencies: PostgreSQL analytics queries

**11. Notification Module**
- Endpoints: Internal service (no direct HTTP endpoints)
- Responsibilities: Push notification dispatch via FCM, notification template management
- Dependencies: Firebase Admin SDK for Node.js

**12. WebSocket Module**
- Events: `order:status_changed`, `rider:location_update`, `delivery:request`, `dispute:resolved`
- Responsibilities: Real-time event broadcasting to connected clients
- Dependencies: Socket.io, JWT authentication for WebSocket connections

### Authentication Flow

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant DB
    
    Client->>API: POST /auth/register {email, password, role}
    API->>API: Hash password with bcrypt
    API->>DB: INSERT user record
    API->>API: Generate JWT (15min) + Refresh Token (7d)
    API->>DB: Store refresh token hash
    API-->>Client: {jwt, refreshToken, user}
    
    Note over Client: JWT expires after 15 minutes
    
    Client->>API: POST /auth/refresh {refreshToken}
    API->>DB: Verify refresh token hash
    API->>API: Generate new JWT
    API-->>Client: {jwt}
    
    Client->>API: GET /protected-endpoint {Authorization: Bearer JWT}
    API->>API: Verify JWT signature & expiry
    API->>API: Check role permissions
    API-->>Client: Protected resource
```

### Order Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> pending_payment: Customer confirms checkout
    pending_payment --> confirmed: Chapa payment success
    pending_payment --> payment_failed: Chapa payment failure/timeout
    payment_failed --> [*]
    
    confirmed --> ready_for_pickup: Restaurant marks ready
    confirmed --> cancelled: Customer cancels
    
    ready_for_pickup --> rider_assigned: Rider accepts
    ready_for_pickup --> cancelled: Customer cancels
    ready_for_pickup --> ready_for_pickup: Rider declines (retry next)
    
    rider_assigned --> picked_up: Rider confirms pickup
    
    picked_up --> delivered: Rider confirms delivery
    
    delivered --> [*]
    cancelled --> [*]
```

### Rider Dispatch Algorithm

The dispatch strategy uses a sequential fallback approach:

1. **Identify candidates**: Query all riders with `status = 'available'` within configurable radius (default 5km) of restaurant
2. **Sort by distance**: Calculate straight-line distance using Haversine formula, sort ascending
3. **Sequential dispatch**:
   - Send WebSocket `delivery:request` event to nearest rider
   - Start 60-second timeout
   - If rider accepts: assign and exit
   - If rider declines or timeout: move to next nearest rider
   - Repeat until rider accepts or candidate list exhausted
4. **Escalation**: If no rider accepts within 10 minutes, send admin alert and keep order in `ready_for_pickup` status

```mermaid
flowchart TD
    START[Order ready_for_pickup] --> QUERY[Query available riders<br/>within 5km radius]
    QUERY --> SORT[Sort by distance<br/>ascending]
    SORT --> CHECK{Riders<br/>available?}
    CHECK -->|No| ALERT[Alert admin<br/>Keep in ready_for_pickup]
    CHECK -->|Yes| SEND[Send request to<br/>nearest rider]
    SEND --> WAIT[Wait 60 seconds]
    WAIT --> RESPONSE{Response?}
    RESPONSE -->|Accept| ASSIGN[Assign rider<br/>Update to rider_assigned]
    RESPONSE -->|Decline| NEXT[Move to next rider]
    RESPONSE -->|Timeout| NEXT
    NEXT --> CHECK2{More<br/>riders?}
    CHECK2 -->|Yes| SEND
    CHECK2 -->|No| TIMEOUT{10 min<br/>elapsed?}
    TIMEOUT -->|Yes| ALERT
    TIMEOUT -->|No| QUERY
    ASSIGN --> END[Done]
    ALERT --> END
```

### Delivery Fee Calculation

Formula: `fee = base_fee + (distance_km × rate_per_km)`

Example configuration:
- `base_fee = 5 ETB`
- `rate_per_km = 2 ETB`
- For 3km delivery: `5 + (3 × 2) = 11 ETB`

Implementation:
```javascript
function calculateDeliveryFee(restaurantCoords, customerCoords, config) {
  const distanceKm = haversineDistance(restaurantCoords, customerCoords);
  const fee = config.base_fee + (distanceKm * config.rate_per_km);
  return Math.round(fee * 100) / 100; // Round to 2 decimal places
}
```

The `base_fee` and `rate_per_km` are stored as configurable values in the database (e.g., a `platform_config` table) or environment variables, allowing the admin to adjust pricing without code changes.

---

## Data Models

### Core Entities

**User**
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('customer', 'restaurant', 'rider', 'admin')),
  display_name VARCHAR(100),
  phone VARCHAR(20),
  profile_photo_url TEXT,
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
```

**RefreshToken**
```sql
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
```

**Restaurant**
```sql
CREATE TABLE restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  logo_url TEXT,
  cover_image_url TEXT,
  address TEXT NOT NULL,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')),
  average_rating DECIMAL(3, 2) DEFAULT 0.0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_restaurants_status ON restaurants(status);
CREATE INDEX idx_restaurants_owner_id ON restaurants(owner_id);
```

**MenuItem**
```sql
CREATE TABLE menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price DECIMAL(10, 2) NOT NULL,
  category VARCHAR(100),
  image_url TEXT NOT NULL,
  available BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_menu_items_restaurant_id ON menu_items(restaurant_id);
CREATE INDEX idx_menu_items_available ON menu_items(available);
```

**Address**
```sql
CREATE TABLE addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(50), -- e.g., "Home", "Work"
  address_line TEXT NOT NULL,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  is_default BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_addresses_user_id ON addresses(user_id);
```

**Order**
```sql
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  rider_id UUID REFERENCES users(id),
  delivery_address_id UUID NOT NULL REFERENCES addresses(id),
  status VARCHAR(30) NOT NULL CHECK (status IN (
    'pending_payment', 'payment_failed', 'confirmed', 
    'ready_for_pickup', 'rider_assigned', 'picked_up', 
    'delivered', 'cancelled'
  )),
  subtotal DECIMAL(10, 2) NOT NULL,
  delivery_fee DECIMAL(10, 2) NOT NULL,
  total DECIMAL(10, 2) NOT NULL,
  payment_reference VARCHAR(255),
  payment_status VARCHAR(20),
  cancellation_reason TEXT,
  estimated_prep_time_minutes INT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_restaurant_id ON orders(restaurant_id);
CREATE INDEX idx_orders_rider_id ON orders(rider_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at);
```

**OrderItem**
```sql
CREATE TABLE order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES menu_items(id),
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10, 2) NOT NULL,
  item_name VARCHAR(255) NOT NULL, -- Snapshot for history
  item_image_url TEXT
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
```

**RiderLocation**
```sql
CREATE TABLE rider_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  availability VARCHAR(20) NOT NULL CHECK (availability IN ('available', 'on_delivery', 'offline')),
  timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_rider_locations_rider_id ON rider_locations(rider_id);
CREATE INDEX idx_rider_locations_timestamp ON rider_locations(timestamp);
CREATE INDEX idx_rider_locations_availability ON rider_locations(availability);
```

**Rating**
```sql
CREATE TABLE ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID REFERENCES restaurants(id),
  rider_id UUID REFERENCES users(id),
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(order_id, restaurant_id), -- One restaurant rating per order
  UNIQUE(order_id, rider_id) -- One rider rating per order
);

CREATE INDEX idx_ratings_restaurant_id ON ratings(restaurant_id);
CREATE INDEX idx_ratings_rider_id ON ratings(rider_id);
```

**Dispute**
```sql
CREATE TABLE disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  customer_id UUID NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL,
  evidence_url TEXT,
  status VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  resolution VARCHAR(50) CHECK (resolution IN ('refund', 'partial_refund', 'no_action')),
  refund_amount DECIMAL(10, 2),
  admin_notes TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  resolved_at TIMESTAMP
);

CREATE INDEX idx_disputes_status ON disputes(status);
CREATE INDEX idx_disputes_order_id ON disputes(order_id);
```

**PlatformConfig**
```sql
CREATE TABLE platform_config (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Initial config values
INSERT INTO platform_config (key, value) VALUES
  ('delivery_base_fee', '5.00'),
  ('delivery_rate_per_km', '2.00'),
  ('rider_search_radius_km', '5.0'),
  ('rider_timeout_seconds', '60'),
  ('dispatch_max_duration_minutes', '10');
```

**FCMToken**
```sql
CREATE TABLE fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  device_type VARCHAR(20) CHECK (device_type IN ('ios', 'android', 'web')),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, token)
);

CREATE INDEX idx_fcm_tokens_user_id ON fcm_tokens(user_id);
```

### Relationships

```mermaid
erDiagram
    USERS ||--o{ RESTAURANTS : owns
    USERS ||--o{ ADDRESSES : has
    USERS ||--o{ ORDERS : places
    USERS ||--o{ ORDERS : delivers
    USERS ||--o{ RIDER_LOCATIONS : tracks
    USERS ||--o{ RATINGS : submits
    USERS ||--o{ DISPUTES : raises
    USERS ||--o{ REFRESH_TOKENS : has
    USERS ||--o{ FCM_TOKENS : registers
    
    RESTAURANTS ||--o{ MENU_ITEMS : lists
    RESTAURANTS ||--o{ ORDERS : receives
    RESTAURANTS ||--o{ RATINGS : receives
    
    ORDERS ||--o{ ORDER_ITEMS : contains
    ORDERS ||--o{ RATINGS : generates
    ORDERS ||--o{ DISPUTES : may_have
    
    ADDRESSES ||--o{ ORDERS : delivers_to
    MENU_ITEMS ||--o{ ORDER_ITEMS : includes
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Registration creates account with hashed password and tokens

*For any* valid registration data (email, password, role), submitting it to the registration endpoint should create a user account with a bcrypt-hashed password and return both a JWT and a Refresh_Token.

**Validates: Requirements 1.2**

### Property 2: Duplicate email registration rejected

*For any* email address, if a user is already registered with that email, attempting to register again with the same email should return a 409 Conflict error.

**Validates: Requirements 1.3**

### Property 3: Login with valid credentials returns tokens

*For any* registered user, logging in with correct credentials should return a new JWT and Refresh_Token.

**Validates: Requirements 1.4**

### Property 4: Login with invalid credentials rejected

*For any* combination of email and password where either is incorrect, the login attempt should return a 401 Unauthorized error.

**Validates: Requirements 1.5**

### Property 5: Refresh token exchange issues new JWT

*For any* valid refresh token, submitting it to the refresh endpoint should return a new JWT without requiring re-login.

**Validates: Requirements 1.6**

### Property 6: Invalid refresh token rejected

*For any* expired or malformed refresh token, attempting to use it should return a 401 Unauthorized error.

**Validates: Requirements 1.7**

### Property 7: Logout invalidates refresh token

*For any* user session, after logout, attempting to use the refresh token should fail with a 401 error.

**Validates: Requirements 1.9**

### Property 8: Role-based access control enforced

*For any* protected endpoint and any user with an unauthorized role, access attempts should be rejected with a 403 Forbidden error.

**Validates: Requirements 1.10**

### Property 9: Restaurant registration starts in pending status

*For any* restaurant registration with valid data, the created restaurant record should have status `pending`.

**Validates: Requirements 2.1**

### Property 10: Pending restaurants cannot publish menu items

*For any* restaurant with status `pending`, attempts to create or publish menu items should be rejected.

**Validates: Requirements 2.2**

### Property 11: Restaurant approval makes it visible to customers

*For any* pending restaurant, when an admin approves it, the restaurant status should update to `approved` and appear in customer-facing listings.

**Validates: Requirements 2.3**

### Property 12: Restaurant rejection updates status

*For any* pending restaurant, when an admin rejects it, the restaurant status should update to `rejected`.

**Validates: Requirements 2.4**

### Property 13: Image URLs stored in restaurant record

*For any* restaurant with uploaded logo or cover image, the Cloudinary URLs should be persisted in the restaurant record.

**Validates: Requirements 2.6**

### Property 14: Incomplete restaurant data rejected

*For any* restaurant registration data missing required fields (name, address, coordinates), the backend should return a 422 Unprocessable Entity error listing the missing fields.

**Validates: Requirements 2.7**

### Property 15: Menu item creation requires all fields

*For any* menu item creation request missing required fields (name, description, price, category, image), the backend should reject it with a 422 error.

**Validates: Requirements 3.2**

### Property 16: Menu item image URL stored

*For any* menu item with an uploaded image, the Cloudinary URL should be stored in the menu_items record.

**Validates: Requirements 3.3**

### Property 17: Menu item availability toggle

*For any* menu item, toggling its availability status should update the `available` field correctly.

**Validates: Requirements 3.4**

### Property 18: Unavailable menu items excluded from customer queries

*For any* customer-facing menu query, all returned menu items should have `available = true`.

**Validates: Requirements 3.5**

### Property 19: Menu items grouped by category

*For any* menu query requesting items by category, all returned items should belong to the specified category.

**Validates: Requirements 3.6**

### Property 20: Deleting menu item in active order marks unavailable

*For any* menu item that appears in an order with status other than `delivered` or `cancelled`, attempting to delete it should mark it as `unavailable` instead of removing the record.

**Validates: Requirements 3.7**

### Property 21: Customer listings show only approved restaurants

*For any* customer-facing restaurant listing query, all returned restaurants should have status `approved`.

**Validates: Requirements 4.1**

### Property 22: Restaurant category filter works correctly

*For any* category filter applied to restaurant listings, all returned restaurants should match the specified category.

**Validates: Requirements 4.2**

### Property 23: Search query matches case-insensitively

*For any* search query string, all returned restaurants and menu items should have names or descriptions that match the query in a case-insensitive manner.

**Validates: Requirements 4.3**

### Property 24: Listing endpoints return paginated results

*For any* listing endpoint request, the response should contain paginated results with a maximum of 20 items per page (or the specified page size).

**Validates: Requirements 4.4**

### Property 25: Checkout validates item availability

*For any* cart containing unavailable menu items, the checkout validation should reject the request and identify the unavailable items.

**Validates: Requirements 5.5**

### Property 26: Order creation starts in pending_payment

*For any* checkout request with valid cart data, the created order should have status `pending_payment`.

**Validates: Requirements 6.1**

### Property 27: Order creation returns payment URL

*For any* order creation request, the backend should initiate a Chapa payment session and return a payment URL.

**Validates: Requirements 6.2**

### Property 28: Successful payment webhook updates order to confirmed

*For any* order in `pending_payment` status, receiving a valid Chapa success webhook should update the order status to `confirmed`.

**Validates: Requirements 6.3**

### Property 29: Failed payment webhook updates order to payment_failed

*For any* order in `pending_payment` status, receiving a valid Chapa failure webhook should update the order status to `payment_failed`.

**Validates: Requirements 6.4**

### Property 30: Invalid webhook signature rejected

*For any* Chapa webhook request with an invalid signature, the backend should reject it without processing the payment event.

**Validates: Requirements 6.5**

### Property 31: Confirmed order stores payment details

*For any* order that transitions to `confirmed` status, the payment reference, amount, and timestamp should be recorded in the order record.

**Validates: Requirements 6.6**

### Property 32: Expired payment session marks order failed

*For any* payment session that expires without completion, the order status should update to `payment_failed`.

**Validates: Requirements 6.8**

### Property 33: Confirmed order triggers restaurant WebSocket notification

*For any* order that transitions to `confirmed` status, a WebSocket notification containing full order details should be sent to the restaurant.

**Validates: Requirements 7.1**

### Property 34: Orders auto-confirmed on successful payment

*For any* order with a successful payment, the order should transition to `confirmed` status without requiring manual restaurant acceptance.

**Validates: Requirements 7.3**

### Property 35: Ready for pickup triggers rider dispatch

*For any* order marked as `ready_for_pickup`, the backend should begin the rider dispatch process.

**Validates: Requirements 7.5**

### Property 36: Dispatch identifies riders within radius

*For any* order in `ready_for_pickup` status, the dispatch system should identify all riders with status `available` within the configured radius of the restaurant.

**Validates: Requirements 8.1**

### Property 37: Dispatch sends request to nearest rider first

*For any* order dispatch with multiple available riders, the first delivery request should be sent to the rider with the smallest distance from the restaurant.

**Validates: Requirements 8.2**

### Property 38: Rider acceptance updates order and rider status

*For any* delivery request, when a rider accepts it, the order status should update to `rider_assigned` and the rider status should update to `on_delivery`.

**Validates: Requirements 8.4**

### Property 39: Rider decline triggers next rider contact

*For any* delivery request, when a rider declines it, the request should immediately be sent to the next nearest available rider.

**Validates: Requirements 8.5**

### Property 40: Unaccepted delivery after timeout alerts admin

*For any* delivery request where no rider accepts within 10 minutes, an admin alert should be generated and the order should remain in `ready_for_pickup` status.

**Validates: Requirements 8.6**

### Property 41: Pickup confirmation updates order status

*For any* order in `rider_assigned` status, when the rider confirms pickup, the order status should update to `picked_up`.

**Validates: Requirements 8.7**

### Property 42: Delivery confirmation updates order and rider status

*For any* order in `picked_up` status, when the rider confirms delivery, the order status should update to `delivered` and the rider status should update to `available`.

**Validates: Requirements 8.8**

### Property 43: Order status transitions trigger customer WebSocket notifications

*For any* order status transition, a WebSocket notification should be sent to the customer.

**Validates: Requirements 9.1**

### Property 44: Rider location updates broadcast to customer

*For any* rider location update received while an order is in `picked_up` status, the location should be broadcast to the customer via WebSocket.

**Validates: Requirements 9.6**

### Property 45: Valid rating submission stored

*For any* delivered order and valid rating data (1-5 stars, optional review), the rating should be stored for both restaurant and rider.

**Validates: Requirements 10.2**

### Property 46: Duplicate rating rejected

*For any* order that already has a rating, attempting to submit another rating should return a 409 Conflict error.

**Validates: Requirements 10.3**

### Property 47: Average rating recalculated on new submission

*For any* new rating submission, the average rating for the restaurant and rider should be recalculated and updated.

**Validates: Requirements 10.4**

### Property 48: Suspended restaurant hidden and orders cancelled

*For any* approved restaurant, when it is suspended, it should be hidden from customer listings and all active orders from that restaurant should be cancelled.

**Validates: Requirements 11.4**

### Property 49: Suspended user tokens invalidated and login rejected

*For any* user account that is suspended, all active refresh tokens should be invalidated and new login attempts should be rejected.

**Validates: Requirements 12.3**

### Property 50: Dispute submission creates record

*For any* delivered or failed order, when a customer raises a dispute with a reason, a dispute record should be created and linked to the order.

**Validates: Requirements 13.2**

### Property 51: Refund resolution initiates Chapa refund

*For any* dispute resolved with outcome `refund` or `partial_refund`, a Chapa refund should be initiated for the specified amount.

**Validates: Requirements 13.5**

### Property 52: Dispute resolution triggers customer notification

*For any* dispute that is resolved, a WebSocket notification containing the outcome should be sent to the customer.

**Validates: Requirements 13.6**

### Property 53: Order status change triggers customer push notification

*For any* order that transitions to `rider_assigned`, `picked_up`, or `delivered` status, a push notification should be sent to the customer via FCM.

**Validates: Requirements 15.1**

### Property 54: Confirmed order triggers restaurant push notification

*For any* order that transitions to `confirmed` status, a push notification should be sent to the restaurant via FCM.

**Validates: Requirements 15.2**

### Property 55: Delivery request triggers rider push notification

*For any* delivery request sent to a rider, a push notification should be sent to that rider via FCM.

**Validates: Requirements 15.3**

### Property 56: Delivery fee calculated correctly

*For any* restaurant coordinates, customer coordinates, base_fee, and rate_per_km, the delivery fee should equal `base_fee + (distance_km × rate_per_km)`.

**Validates: Requirements 16.1**

### Property 57: Distance calculated using Haversine formula

*For any* two coordinate pairs (latitude, longitude), the straight-line distance in kilometers should be calculated correctly using the Haversine formula.

**Validates: Requirements 16.3**

### Property 58: Significant distance deviation triggers fee recalculation

*For any* order where the actual delivery distance deviates from the estimate by more than 20%, the delivery fee should be recalculated before order finalization.

**Validates: Requirements 16.6**

### Property 59: Confirmed order cancellation triggers refund

*For any* order with status `confirmed`, when the customer cancels it, the order status should update to `cancelled` and a full Chapa refund should be initiated.

**Validates: Requirements 17.2**

### Property 60: Ready for pickup cancellation triggers refund and notification

*For any* order with status `ready_for_pickup`, when the customer cancels it, the order status should update to `cancelled`, the restaurant should be notified, and a full Chapa refund should be initiated.

**Validates: Requirements 17.3**

### Property 61: Cancellation rejected for assigned or picked up orders

*For any* order with status `rider_assigned` or `picked_up`, customer cancellation requests should be rejected with a 409 Conflict error.

**Validates: Requirements 17.4**

### Property 62: Cancellation records reason and timestamp

*For any* cancelled order, the cancellation reason and timestamp should be stored in the order record.

**Validates: Requirements 17.5**

### Property 63: Rider location updates stored with timestamp

*For any* rider location update received, the location and timestamp should be stored in the rider_locations table.

**Validates: Requirements 18.4**

### Property 64: Recent rider location used for dispatch

*For any* rider with a location update no more than 5 minutes old, that location should be used for dispatch distance calculations.

**Validates: Requirements 18.6**

### Property 65: Profile photo URL stored

*For any* user profile photo upload, the Cloudinary URL should be stored in the user record.

**Validates: Requirements 19.2**

### Property 66: Invalid phone number rejected

*For any* phone number that does not conform to the valid format, profile update requests should be rejected with a validation error.

**Validates: Requirements 19.4**

### Property 67: Password change requires current password

*For any* password change request, if the provided current password is incorrect, the request should be rejected.

**Validates: Requirements 19.5**

### Property 68: API responses follow consistent envelope

*For any* API response, it should follow the structure `{ "success": boolean, "data": any, "error": string | null }`.

**Validates: Requirements 20.1**

### Property 69: Invalid request bodies return 422

*For any* request body that fails schema validation, the backend should return a 422 Unprocessable Entity error.

**Validates: Requirements 20.2**

### Property 70: Multi-step operations use transactions

*For any* multi-step operation (e.g., order creation + payment initiation), either all database writes succeed or all fail (no partial writes).

**Validates: Requirements 20.3**

### Property 71: Webhook idempotency prevents duplicates

*For any* Chapa webhook, if the same webhook is delivered multiple times (same payment reference), it should not create duplicate payment records.

**Validates: Requirements 20.4**

### Property 72: Non-existent resources return 404

*For any* request to a resource ID that does not exist, the backend should return a 404 Not Found error.

**Validates: Requirements 20.6**

### Property 73: Unauthorized resource access returns 403

*For any* request to a resource that the authenticated user does not own, the backend should return a 403 Forbidden error.

**Validates: Requirements 20.6**

---

## Error Handling

### Error Response Format

All error responses follow the consistent JSON envelope:

```json
{
  "success": false,
  "data": null,
  "error": "Human-readable error message"
}
```

### HTTP Status Codes

The backend uses standard HTTP status codes:

- **200 OK**: Successful GET, PUT, or DELETE
- **201 Created**: Successful POST that creates a resource
- **400 Bad Request**: Malformed request syntax
- **401 Unauthorized**: Missing, expired, or invalid JWT
- **403 Forbidden**: Valid JWT but insufficient permissions
- **404 Not Found**: Resource does not exist
- **409 Conflict**: Request conflicts with current state (e.g., duplicate email, duplicate rating)
- **422 Unprocessable Entity**: Request body fails validation
- **500 Internal Server Error**: Unexpected server error

### Validation Errors

Validation errors (422) include detailed field-level information:

```json
{
  "success": false,
  "data": null,
  "error": "Validation failed",
  "details": [
    { "field": "email", "message": "Invalid email format" },
    { "field": "password", "message": "Password must be at least 8 characters" }
  ]
}
```

### External Service Failures

**Chapa Payment Failures:**
- If Chapa API is unreachable during payment initiation, return 503 Service Unavailable
- If payment webhook signature verification fails, log the event and return 401 to Chapa
- If payment webhook processing fails, return 500 to Chapa (Chapa will retry)

**Cloudinary Upload Failures:**
- If Cloudinary API is unreachable, return 503 Service Unavailable
- If upload fails due to invalid file format, return 422 with descriptive error

**Firebase Cloud Messaging Failures:**
- If FCM API is unreachable, log the error but do not fail the primary operation (e.g., order status update)
- Implement retry logic with exponential backoff for failed push notifications

**Google Maps API Failures:**
- If geocoding fails, return 422 with error message
- If distance calculation fails, use fallback straight-line distance

### Database Errors

- Connection failures: Return 503 Service Unavailable
- Constraint violations: Return 409 Conflict with descriptive message
- Transaction failures: Roll back all changes and return 500 Internal Server Error

### WebSocket Error Handling

- If WebSocket connection fails, clients should implement exponential backoff reconnection
- If a WebSocket message fails to deliver, log the error but do not block the operation
- Clients should poll REST endpoints as fallback if WebSocket connection is unavailable

### Logging

All errors are logged with:
- Timestamp (ISO 8601)
- Request ID (UUID generated per request)
- User ID (if authenticated)
- HTTP method and path
- Error message and stack trace
- Request body (sanitized to remove sensitive data)

Logs are written to stdout in JSON format for Railway log aggregation.

---

## Testing Strategy

### Dual Testing Approach

The testing strategy employs both unit tests and property-based tests to ensure comprehensive coverage:

**Unit Tests:**
- Verify specific examples and edge cases
- Test integration points between components
- Validate error conditions and boundary cases
- Test external service mocking (Chapa, Cloudinary, FCM)

**Property-Based Tests:**
- Verify universal properties across all inputs
- Use randomized input generation to discover edge cases
- Ensure correctness properties hold for all valid data
- Each property test runs a minimum of 100 iterations

Together, unit tests catch concrete bugs while property tests verify general correctness.

### Property-Based Testing Configuration

**Library Selection:**
- Backend (Node.js): Use `fast-check` for property-based testing
- Flutter Apps: Use `test` package with custom generators or `faker` for randomized data

**Test Configuration:**
- Minimum 100 iterations per property test (due to randomization)
- Each property test must reference its design document property
- Tag format: `// Feature: food-delivery-app, Property {number}: {property_text}`

**Example Property Test (Node.js with fast-check):**

```javascript
const fc = require('fast-check');
const { registerUser } = require('./auth');

// Feature: food-delivery-app, Property 2: Duplicate email registration rejected
test('duplicate email registration should return 409', async () => {
  await fc.assert(
    fc.asyncProperty(
      fc.emailAddress(),
      fc.string({ minLength: 8 }),
      fc.constantFrom('customer', 'restaurant', 'rider'),
      async (email, password, role) => {
        // First registration should succeed
        const result1 = await registerUser({ email, password, role });
        expect(result1.success).toBe(true);
        
        // Second registration with same email should fail with 409
        const result2 = await registerUser({ email, password: 'different', role });
        expect(result2.status).toBe(409);
      }
    ),
    { numRuns: 100 }
  );
});
```

### Unit Testing Strategy

**Backend Unit Tests:**
- Test each API endpoint with valid and invalid inputs
- Mock external services (Chapa, Cloudinary, FCM, Google Maps)
- Test middleware (authentication, authorization, validation)
- Test database queries and transactions
- Test WebSocket event emission
- Test utility functions (Haversine distance, fee calculation)

**Flutter Unit Tests:**
- Test state management (Riverpod providers)
- Test HTTP client interactions (Dio)
- Test data models and serialization
- Test business logic (cart management, validation)
- Mock backend API responses

**Integration Tests:**
- Test complete order lifecycle from creation to delivery
- Test payment webhook handling end-to-end
- Test rider dispatch algorithm with multiple riders
- Test WebSocket connection and message delivery
- Test authentication flow with token refresh

**End-to-End Tests:**
- Test critical user journeys (customer order flow, restaurant order management, rider delivery)
- Use Postman or similar tool for API testing
- Use Flutter integration tests for mobile app flows

### Test Coverage Goals

- Backend: Minimum 80% code coverage
- Flutter Apps: Minimum 70% code coverage for business logic
- All correctness properties must have corresponding property-based tests
- All error conditions must have unit tests

### Continuous Integration

- Run all tests on every commit
- Block merges if tests fail
- Generate coverage reports
- Run property-based tests with increased iterations (500+) in CI

---

## Deployment and Operations

### Environment Configuration

**Environment Variables:**
```
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://user:pass@db.supabase.co:5432/postgres
JWT_SECRET=<random-secret>
JWT_EXPIRY=15m
REFRESH_TOKEN_EXPIRY=7d
CHAPA_SECRET_KEY=<chapa-secret>
CHAPA_WEBHOOK_SECRET=<chapa-webhook-secret>
CLOUDINARY_CLOUD_NAME=<cloud-name>
CLOUDINARY_API_KEY=<api-key>
CLOUDINARY_API_SECRET=<api-secret>
FIREBASE_PROJECT_ID=<project-id>
FIREBASE_PRIVATE_KEY=<private-key>
FIREBASE_CLIENT_EMAIL=<client-email>
MAPBOX_ACCESS_TOKEN=<mapbox-token>
RIDER_SEARCH_RADIUS_KM=5
RIDER_TIMEOUT_SECONDS=60
DISPATCH_MAX_DURATION_MINUTES=10
DELIVERY_BASE_FEE=5.00
DELIVERY_RATE_PER_KM=2.00
```

### Database Migrations

Use a migration tool (e.g., `node-pg-migrate` or Prisma Migrate) to manage schema changes:
- Version all schema changes
- Run migrations automatically on deployment
- Test migrations on staging before production

### Monitoring and Observability

**Metrics to Track:**
- API response times (p50, p95, p99)
- Error rates by endpoint
- WebSocket connection count
- Active orders by status
- Rider availability count
- Payment success/failure rates
- Push notification delivery rates

**Logging:**
- Structured JSON logs to stdout
- Log levels: ERROR, WARN, INFO, DEBUG
- Include request IDs for tracing

**Alerting:**
- Alert on error rate > 5%
- Alert on API response time p95 > 2 seconds
- Alert on database connection failures
- Alert on Chapa webhook failures
- Alert on unassigned orders > 10 minutes

### Scaling Considerations

**Horizontal Scaling:**
- Backend API is stateless and can scale horizontally
- Use Render's auto-scaling
- WebSocket connections require sticky sessions or Redis adapter for Socket.io

**Database Scaling:**
- Use connection pooling (pg-pool)
- Add read replicas for analytics queries
- Index frequently queried columns (already defined in schema)

**Caching:**
- Cache restaurant listings with Redis (TTL: 5 minutes)
- Cache menu items with Redis (TTL: 5 minutes)
- Invalidate cache on restaurant/menu updates

**Rate Limiting:**
- Implement rate limiting per user (e.g., 100 requests/minute)
- Implement rate limiting per IP for unauthenticated endpoints

### Security Considerations

**Authentication:**
- Use HTTPS for all API communication
- Store JWT secret securely (environment variable)
- Rotate JWT secret periodically
- Implement refresh token rotation

**Authorization:**
- Enforce role-based access control on all endpoints
- Validate resource ownership before allowing access

**Input Validation:**
- Validate all request bodies against schemas
- Sanitize user input to prevent SQL injection
- Validate file uploads (type, size)

**External Services:**
- Verify Chapa webhook signatures
- Use Cloudinary signed uploads for sensitive images
- Validate Mapbox API responses

**Data Protection:**
- Hash passwords with bcrypt (cost factor: 10)
- Do not log sensitive data (passwords, tokens, payment details)
- Implement GDPR-compliant data deletion

---

## Future Enhancements

**Phase 2 Features:**
- Scheduled orders (order for future delivery)
- Promo codes and discounts
- Restaurant operating hours and automatic unavailability
- Multi-restaurant orders (single delivery from multiple restaurants)
- Rider earnings dashboard
- Customer loyalty program

**Technical Improvements:**
- GraphQL API for more flexible client queries
- Server-sent events (SSE) as WebSocket alternative
- Redis caching layer
- Elasticsearch for advanced search
- Automated testing with Playwright for admin dashboard
- Mobile app offline mode with local database sync

---

## Appendix

### Haversine Distance Formula

```javascript
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distance = R * c;
  
  return distance;
}

function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}
```

### WebSocket Event Schemas

**order:status_changed**
```json
{
  "event": "order:status_changed",
  "data": {
    "orderId": "uuid",
    "status": "confirmed",
    "timestamp": "2024-01-15T10:30:00Z",
    "order": { /* full order object */ }
  }
}
```

**rider:location_update**
```json
{
  "event": "rider:location_update",
  "data": {
    "riderId": "uuid",
    "orderId": "uuid",
    "latitude": 9.0320,
    "longitude": 38.7469,
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

**delivery:request**
```json
{
  "event": "delivery:request",
  "data": {
    "orderId": "uuid",
    "restaurantName": "Pizza Palace",
    "restaurantAddress": "123 Main St",
    "customerAddress": "456 Oak Ave",
    "deliveryFee": 11.00,
    "estimatedDistance": 3.0,
    "expiresAt": "2024-01-15T10:31:00Z"
  }
}
```

**dispute:resolved**
```json
{
  "event": "dispute:resolved",
  "data": {
    "disputeId": "uuid",
    "orderId": "uuid",
    "resolution": "refund",
    "refundAmount": 50.00,
    "adminNotes": "Customer complaint verified",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

### API Endpoint Summary

**Authentication:**
- `POST /auth/register` - Register new user
- `POST /auth/login` - Login user
- `POST /auth/refresh` - Refresh JWT
- `POST /auth/logout` - Logout user

**Users:**
- `GET /users/profile` - Get user profile
- `PUT /users/profile` - Update user profile
- `PUT /users/password` - Change password
- `POST /users/addresses` - Add delivery address
- `GET /users/addresses` - List delivery addresses
- `DELETE /users/addresses/:id` - Delete delivery address

**Restaurants:**
- `POST /restaurants` - Register restaurant
- `GET /restaurants` - List restaurants (customer view)
- `GET /restaurants/:id` - Get restaurant details
- `PUT /restaurants/:id` - Update restaurant (owner only)
- `POST /restaurants/:id/approve` - Approve restaurant (admin only)
- `PUT /restaurants/:id/suspend` - Suspend restaurant (admin only)

**Menu:**
- `POST /restaurants/:id/menu` - Create menu item
- `GET /restaurants/:id/menu` - List menu items
- `PUT /menu/:id` - Update menu item
- `DELETE /menu/:id` - Delete menu item
- `PUT /menu/:id/availability` - Toggle availability

**Orders:**
- `POST /orders` - Create order
- `GET /orders` - List user's orders
- `GET /orders/:id` - Get order details
- `PUT /orders/:id/cancel` - Cancel order
- `PUT /orders/:id/status` - Update order status (restaurant/rider only)
- `POST /orders/:id/rate` - Rate order (customer only)

**Payments:**
- `POST /payments/webhook` - Chapa webhook handler
- `POST /payments/refund` - Initiate refund (admin only)
- `GET /payments/estimate-fee` - Estimate delivery fee

**Riders:**
- `GET /riders/available` - List available riders (internal)
- `PUT /riders/location` - Update rider location
- `PUT /riders/availability` - Toggle rider availability

**Deliveries:**
- `POST /deliveries/:id/accept` - Accept delivery request
- `POST /deliveries/:id/decline` - Decline delivery request
- `PUT /deliveries/:id/pickup` - Confirm pickup
- `PUT /deliveries/:id/deliver` - Confirm delivery

**Disputes:**
- `POST /disputes` - Raise dispute
- `GET /disputes` - List disputes (admin only)
- `PUT /disputes/:id/resolve` - Resolve dispute (admin only)

**Admin:**
- `GET /admin/restaurants` - List all restaurants
- `GET /admin/users` - List all users
- `PUT /admin/users/:id/suspend` - Suspend user
- `GET /admin/analytics` - Get platform analytics

---

**End of Design Document**
