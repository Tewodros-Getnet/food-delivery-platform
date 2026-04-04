# Requirements Document

## Introduction

A full-stack food delivery platform similar to Uber Eats / DoorDash. The platform connects customers who want food delivered, restaurants that prepare the food, and riders who deliver it — all coordinated by a backend that acts as the central relay. A web-based admin dashboard gives the platform owner full visibility and control.

The system consists of four clients:
- **Customer Mobile App** (Flutter) — browse, order, pay, track, review
- **Restaurant Mobile App** (Flutter) — manage menu, receive orders, mark food ready
- **Rider Mobile App** (Flutter) — accept delivery requests, navigate, update location
- **Admin Web Dashboard** (Next.js) — approve restaurants, manage users, handle disputes, view analytics

The backend is a Node.js + Express REST API backed by PostgreSQL (hosted on Supabase), with WebSockets for real-time order status updates, Cloudinary for image storage, Chapa for payments, JWT-based auth with refresh tokens, and Firebase Cloud Messaging (FCM) for push notifications. The Flutter apps use Dio for HTTP requests and Riverpod for state management. The platform backend is deployed on Render, the admin dashboard on Vercel, and the database on Supabase.

---

## Glossary

- **System**: The food delivery platform as a whole (backend + all clients)
- **Backend**: The Node.js REST API server
- **Customer**: A registered user who places food orders
- **Restaurant**: A registered and admin-approved food vendor
- **Rider**: A registered delivery agent
- **Admin**: The platform owner operating the web dashboard
- **Order**: A confirmed, paid request from a Customer for items from a single Restaurant
- **Cart**: A temporary collection of menu items a Customer intends to order
- **Menu_Item**: A food or drink item listed by a Restaurant with a name, description, price, and image
- **Delivery_Request**: A notification sent by the Backend to available Riders when an Order is ready for pickup
- **Order_Status**: The current lifecycle state of an Order (see Order Flow)
- **JWT**: JSON Web Token used for stateless authentication
- **Refresh_Token**: A long-lived token used to obtain a new JWT without re-login
- **WebSocket**: A persistent bidirectional connection used for real-time status push
- **Chapa**: The payment gateway used to process Customer payments
- **Cloudinary**: The cloud image storage service used for menu item and profile images
- **Railway**: ~~The cloud deployment platform~~ (replaced — see Render/Supabase/Vercel)
- **Render**: The cloud platform hosting the Backend API
- **Supabase**: The managed PostgreSQL database platform
- **Vercel**: The platform hosting the Admin Web Dashboard
- **Mapbox**: The maps and geocoding service used in Flutter apps (replaces Google Maps)
- **Riverpod**: The state management library used in the Flutter apps
- **Dio**: The HTTP client library used in the Flutter apps

---

## Requirements

### Requirement 1: User Registration and Authentication

**User Story:** As a user (Customer, Restaurant owner, or Rider), I want to register and log in securely, so that I can access the features relevant to my role.

#### Acceptance Criteria

1. THE Backend SHALL expose separate registration endpoints for Customer, Restaurant, and Rider roles.
2. WHEN a user submits valid registration data, THE Backend SHALL create an account, hash the password using bcrypt, and return a JWT and a Refresh_Token.
3. WHEN a user submits a registration request with an email that already exists, THE Backend SHALL return a 409 Conflict error with a descriptive message.
4. WHEN a user submits a login request with valid credentials, THE Backend SHALL return a new JWT and a Refresh_Token.
5. WHEN a user submits a login request with invalid credentials, THE Backend SHALL return a 401 Unauthorized error.
6. WHEN a JWT expires and the client submits a valid Refresh_Token, THE Backend SHALL issue a new JWT without requiring re-login.
7. WHEN a client submits an expired or invalid Refresh_Token, THE Backend SHALL return a 401 Unauthorized error and require re-login.
8. THE Flutter_App SHALL store the JWT and Refresh_Token using flutter_secure_storage.
9. WHEN a user logs out, THE Backend SHALL invalidate the Refresh_Token so it cannot be reused.
10. THE Backend SHALL enforce role-based access control so that each endpoint is accessible only to the authorized role(s).

---

### Requirement 2: Restaurant Onboarding and Admin Approval

**User Story:** As a Restaurant owner, I want to register my restaurant and submit it for approval, so that I can start receiving orders once approved.

#### Acceptance Criteria

1. WHEN a Restaurant owner completes registration, THE Backend SHALL create a Restaurant record with status `pending`.
2. WHILE a Restaurant has status `pending`, THE Backend SHALL reject any attempt by that Restaurant to publish menu items or receive orders.
3. WHEN an Admin approves a Restaurant, THE Backend SHALL update the Restaurant status to `approved` and make it visible to Customers.
4. WHEN an Admin rejects a Restaurant, THE Backend SHALL update the Restaurant status to `rejected` and notify the Restaurant owner.
5. THE Restaurant_App SHALL allow the owner to upload a restaurant logo and cover image via Cloudinary.
6. THE Backend SHALL store the Cloudinary image URLs in the Restaurant record.
7. WHEN a Restaurant owner submits incomplete registration data (missing required fields), THE Backend SHALL return a 422 Unprocessable Entity error listing the missing fields.

---

### Requirement 3: Menu Management

**User Story:** As a Restaurant owner, I want to manage my menu, so that Customers can see accurate, up-to-date items and prices.

#### Acceptance Criteria

1. THE Restaurant_App SHALL allow the owner to create, update, and delete Menu_Items.
2. WHEN a Restaurant owner creates a Menu_Item, THE Backend SHALL require a name, description, price, category, and at least one image.
3. WHEN a Menu_Item image is uploaded, THE Restaurant_App SHALL upload it to Cloudinary and THE Backend SHALL store the returned URL.
4. THE Backend SHALL allow Menu_Items to be marked as `available` or `unavailable`.
5. WHILE a Menu_Item is marked `unavailable`, THE Backend SHALL exclude it from Customer-facing menu responses.
6. THE Backend SHALL support grouping Menu_Items into categories (e.g., "Starters", "Mains", "Drinks").
7. WHEN a Restaurant owner deletes a Menu_Item that is part of an active Order, THE Backend SHALL mark the item as `unavailable` rather than deleting it, to preserve Order history integrity.

---

### Requirement 4: Customer Browse and Search

**User Story:** As a Customer, I want to browse and search for restaurants and menu items, so that I can find food I want to order.

#### Acceptance Criteria

1. THE Backend SHALL return only `approved` Restaurants in Customer-facing listing endpoints.
2. THE Backend SHALL support filtering Restaurants by category (e.g., "Pizza", "Ethiopian", "Burgers").
3. WHEN a Customer submits a search query, THE Backend SHALL return Restaurants and Menu_Items whose names or descriptions match the query (case-insensitive).
4. THE Backend SHALL return paginated results for all listing endpoints, with a default page size of 20.
5. THE Customer_App SHALL display each Restaurant's name, cover image, average rating, and estimated delivery time.
6. THE Customer_App SHALL display each Menu_Item's name, description, price, and image.

---

### Requirement 5: Cart Management

**User Story:** As a Customer, I want to manage a cart before placing an order, so that I can review and adjust my selections before paying.

#### Acceptance Criteria

1. THE Customer_App SHALL maintain a Cart locally on the device using Riverpod state.
2. THE Customer_App SHALL allow the Customer to add, remove, and update the quantity of Menu_Items in the Cart.
3. WHEN a Customer adds a Menu_Item from a different Restaurant than items already in the Cart, THE Customer_App SHALL prompt the Customer to clear the existing Cart before adding the new item.
4. THE Customer_App SHALL display the Cart subtotal, estimated delivery fee, and total in real time as items are added or removed.
5. WHEN a Customer proceeds to checkout, THE Customer_App SHALL validate that all Cart items are still `available` by calling the Backend before initiating payment.
6. IF any Cart item is no longer available, THEN THE Customer_App SHALL notify the Customer and remove the unavailable item from the Cart.

---

### Requirement 6: Order Placement and Payment

**User Story:** As a Customer, I want to place an order and pay securely, so that my food gets prepared and delivered.

#### Acceptance Criteria

1. WHEN a Customer confirms checkout, THE Backend SHALL create an Order record with status `pending_payment`.
2. THE Backend SHALL initiate a Chapa payment session and return the payment URL to the Customer_App.
3. WHEN Chapa confirms a successful payment via webhook, THE Backend SHALL update the Order status to `confirmed` and notify the Restaurant via WebSocket.
4. WHEN Chapa reports a failed payment via webhook, THE Backend SHALL update the Order status to `payment_failed` and notify the Customer via WebSocket.
5. THE Backend SHALL verify the Chapa webhook signature before processing any payment event.
6. WHEN an Order is confirmed, THE Backend SHALL record the payment reference, amount, and timestamp.
7. THE Customer_App SHALL display a payment confirmation screen with the Order ID and estimated delivery time after successful payment.
8. IF a Chapa payment session expires without completion, THEN THE Backend SHALL update the Order status to `payment_failed` and release any reserved inventory.

---

### Requirement 7: Restaurant Order Management

**User Story:** As a Restaurant owner, I want to see incoming orders and mark them as ready, so that riders know when to pick up the food.

#### Acceptance Criteria

1. WHEN an Order status changes to `confirmed`, THE Backend SHALL push a WebSocket notification to the Restaurant containing the full Order details.
2. THE Restaurant_App SHALL display incoming Orders in real time via WebSocket.
3. THE Backend SHALL auto-confirm Orders upon successful payment — the Restaurant SHALL NOT be required to manually accept each Order.
4. THE Restaurant_App SHALL allow the owner to mark an Order as `ready_for_pickup`.
5. WHEN a Restaurant marks an Order as `ready_for_pickup`, THE Backend SHALL update the Order status and begin the Rider dispatch process (see Requirement 8).
6. THE Restaurant_App SHALL display the current status of all active Orders.
7. THE Restaurant_App SHALL allow the owner to set an estimated preparation time per Order in minutes.

---

### Requirement 8: Rider Dispatch and Delivery

**User Story:** As a Rider, I want to receive delivery requests and navigate to the restaurant and customer, so that I can complete deliveries efficiently.

#### Acceptance Criteria

1. WHEN an Order status changes to `ready_for_pickup`, THE Backend SHALL identify available Riders within a configurable radius (default: 5 km) of the Restaurant.
2. THE Backend SHALL send a Delivery_Request via WebSocket to the nearest available Rider first.
3. WHEN a Rider does not respond within 60 seconds, THE Backend SHALL send the Delivery_Request to the next nearest available Rider.
4. WHEN a Rider accepts a Delivery_Request, THE Backend SHALL update the Order status to `rider_assigned` and mark the Rider as `on_delivery`.
5. WHEN a Rider declines a Delivery_Request, THE Backend SHALL immediately send the request to the next nearest available Rider.
6. IF no Rider accepts a Delivery_Request within 10 minutes, THEN THE Backend SHALL alert the Admin and keep the Order in `ready_for_pickup` status.
7. WHEN a Rider confirms pickup at the Restaurant, THE Backend SHALL update the Order status to `picked_up`.
8. WHEN a Rider marks an Order as delivered, THE Backend SHALL update the Order status to `delivered` and mark the Rider as `available`.
9. THE Rider_App SHALL display navigation to the Restaurant and then to the Customer using flutter_map with OpenStreetMap.
10. THE Rider_App SHALL allow the Rider to toggle availability between `available` and `offline`.

---

### Requirement 9: Real-Time Order Tracking

**User Story:** As a Customer, I want to track my order in real time, so that I always know where my food is.

#### Acceptance Criteria

1. THE Backend SHALL push WebSocket notifications to the Customer at each Order_Status transition.
2. THE Customer_App SHALL display a live order tracking screen that updates automatically when Order_Status changes.
3. WHEN the Order status is `rider_assigned`, THE Customer_App SHALL display the Rider's name and estimated arrival time.
4. WHEN the Order status is `picked_up`, THE Customer_App SHALL display the Rider's live location on a map using flutter_map with OpenStreetMap.
5. THE Rider_App SHALL send the Rider's GPS coordinates to the Backend every 10 seconds while the Order status is `picked_up`.
6. THE Backend SHALL broadcast the Rider's location update to the Customer via WebSocket.
7. THE Customer_App SHALL display the following status messages at each transition:
   - `confirmed` → "Your order has been confirmed and is being prepared."
   - `ready_for_pickup` → "Your food is ready. A rider is on the way to pick it up."
   - `rider_assigned` → "A rider has been assigned and is heading to the restaurant."
   - `picked_up` → "Your rider has picked up your food and is on the way."
   - `delivered` → "Your order has been delivered. Enjoy your meal."

---

### Requirement 10: Ratings and Reviews

**User Story:** As a Customer, I want to rate my order and leave a review, so that I can share my experience and help others choose.

#### Acceptance Criteria

1. WHEN an Order status changes to `delivered`, THE Customer_App SHALL prompt the Customer to rate the Restaurant and the Rider.
2. THE Backend SHALL accept a rating (integer 1–5) and an optional text review for both the Restaurant and the Rider per completed Order.
3. WHEN a Customer submits a rating for an Order that has already been rated, THE Backend SHALL return a 409 Conflict error.
4. THE Backend SHALL calculate and store the average rating for each Restaurant and each Rider, updated after each new rating submission.
5. THE Customer_App SHALL display the Restaurant's average rating on the restaurant detail screen.
6. THE Rider_App SHALL display the Rider's average rating on the profile screen.

---

### Requirement 11: Admin Dashboard — Restaurant Management

**User Story:** As an Admin, I want to manage restaurants on the platform, so that only legitimate, quality vendors serve customers.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a list of all Restaurants with their current status (`pending`, `approved`, `rejected`, `suspended`).
2. THE Admin_Dashboard SHALL allow the Admin to approve or reject a `pending` Restaurant with an optional reason.
3. THE Admin_Dashboard SHALL allow the Admin to suspend an `approved` Restaurant.
4. WHEN a Restaurant is suspended, THE Backend SHALL hide it from Customer-facing listings and cancel any active Orders from that Restaurant.
5. THE Admin_Dashboard SHALL display the full details of any Restaurant including owner info, images, and menu item count.

---

### Requirement 12: Admin Dashboard — User Management

**User Story:** As an Admin, I want to manage all users on the platform, so that I can handle abuse and maintain platform integrity.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display a searchable, paginated list of all Customers, Riders, and Restaurant owners.
2. THE Admin_Dashboard SHALL allow the Admin to suspend or reactivate any user account.
3. WHEN a user account is suspended, THE Backend SHALL invalidate all active Refresh_Tokens for that user and reject new login attempts.
4. THE Admin_Dashboard SHALL display each user's registration date, order history count, and current status.

---

### Requirement 13: Admin Dashboard — Dispute Management

**User Story:** As an Admin, I want to review and resolve disputes raised by customers or restaurants, so that the platform remains fair and trustworthy.

#### Acceptance Criteria

1. THE Customer_App SHALL allow a Customer to raise a dispute on a delivered or failed Order with a reason and optional evidence (image).
2. THE Backend SHALL create a Dispute record linked to the Order and notify the Admin via the Admin_Dashboard.
3. THE Admin_Dashboard SHALL display all open Disputes with Order details, Customer info, and submitted evidence.
4. THE Admin_Dashboard SHALL allow the Admin to resolve a Dispute by selecting an outcome: `refund`, `partial_refund`, or `no_action`.
5. WHEN the Admin selects `refund` or `partial_refund`, THE Backend SHALL initiate a Chapa refund for the specified amount.
6. WHEN a Dispute is resolved, THE Backend SHALL notify the Customer of the outcome via WebSocket.

---

### Requirement 14: Admin Dashboard — Analytics

**User Story:** As an Admin, I want to view platform analytics, so that I can monitor business performance and make informed decisions.

#### Acceptance Criteria

1. THE Admin_Dashboard SHALL display total orders, total revenue, and active users for a selectable date range.
2. THE Admin_Dashboard SHALL display a breakdown of orders by status (confirmed, delivered, cancelled, failed).
3. THE Admin_Dashboard SHALL display the top 10 Restaurants by order volume for the selected date range.
4. THE Admin_Dashboard SHALL display the top 10 Riders by completed deliveries for the selected date range.
5. THE Backend SHALL expose analytics endpoints that aggregate data from the PostgreSQL database and return results within 2 seconds for date ranges up to 90 days.

---

### Requirement 15: Push Notifications

**User Story:** As a user, I want to receive push notifications for important events, so that I stay informed even when the app is in the background.

#### Acceptance Criteria

1. THE Backend SHALL send push notifications to the Customer when the Order_Status changes to `rider_assigned`, `picked_up`, and `delivered`.
2. THE Backend SHALL send a push notification to the Restaurant when a new Order is confirmed.
3. THE Backend SHALL send a push notification to the Rider when a new Delivery_Request is available.
4. THE Flutter_App SHALL request notification permissions from the device on first launch.
5. WHEN the Flutter_App is in the foreground, THE Flutter_App SHALL display an in-app notification banner instead of a system push notification.
6. THE Backend SHALL use Firebase Admin SDK for Node.js to send push notifications via Firebase Cloud Messaging (FCM).
7. THE Flutter_App SHALL use the `firebase_messaging` package to receive and handle push notifications.

---

### Requirement 16: Delivery Fee Calculation

**User Story:** As a Customer, I want to see a transparent delivery fee before I pay, so that I know the total cost upfront.

#### Acceptance Criteria

1. THE Backend SHALL calculate the delivery fee using the formula: `fee = base_fee + (distance_km × rate_per_km)`.
2. THE Backend SHALL store `base_fee` and `rate_per_km` as configurable values in the database or environment variables.
3. THE Backend SHALL calculate the straight-line distance between the Restaurant and the Customer's delivery address in kilometers.
4. THE Backend SHALL expose a fee estimation endpoint that accepts a Restaurant ID and a delivery address and returns the estimated fee before Order placement.
5. THE Customer_App SHALL display the estimated delivery fee in the Cart summary before the Customer proceeds to checkout.
6. WHEN the actual delivery distance deviates from the estimate by more than 20%, THE Backend SHALL recalculate and apply the corrected fee before finalizing the Order.

---

### Requirement 17: Order Cancellation

**User Story:** As a Customer, I want to cancel an order before it is picked up, so that I am not charged for food I no longer want.

#### Acceptance Criteria

1. WHEN an Order has status `confirmed` or `ready_for_pickup`, THE Customer_App SHALL allow the Customer to request cancellation.
2. WHEN a Customer cancels an Order with status `confirmed`, THE Backend SHALL update the Order status to `cancelled` and initiate a full Chapa refund.
3. WHEN a Customer cancels an Order with status `ready_for_pickup`, THE Backend SHALL update the Order status to `cancelled`, notify the Restaurant, and initiate a full Chapa refund.
4. WHEN an Order has status `rider_assigned` or `picked_up`, THE Backend SHALL reject Customer cancellation requests and return a 409 Conflict error.
5. THE Backend SHALL record the cancellation reason and timestamp on the Order record.

---

### Requirement 18: Rider Location and Availability

**User Story:** As a Rider, I want to manage my availability and share my location, so that the platform can dispatch deliveries to me accurately.

#### Acceptance Criteria

1. THE Rider_App SHALL allow the Rider to toggle between `available` and `offline` status at any time when not on an active delivery.
2. WHILE a Rider has status `available`, THE Rider_App SHALL send GPS coordinates to the Backend every 30 seconds.
3. WHILE a Rider has status `on_delivery`, THE Rider_App SHALL send GPS coordinates to the Backend every 10 seconds.
4. THE Backend SHALL store the Rider's last known location and timestamp in the database.
5. WHEN the Rider_App loses GPS signal for more than 60 seconds during an active delivery, THE Rider_App SHALL display a warning to the Rider and attempt to reconnect.
6. THE Backend SHALL use the Rider's last known location for dispatch calculations if the location is no more than 5 minutes old.

---

### Requirement 19: Profile Management

**User Story:** As any user, I want to manage my profile, so that my information stays accurate and up to date.

#### Acceptance Criteria

1. THE Flutter_App SHALL allow each user to update their display name, phone number, and profile photo.
2. WHEN a user uploads a profile photo, THE Flutter_App SHALL upload it to Cloudinary and THE Backend SHALL store the returned URL.
3. THE Customer_App SHALL allow the Customer to manage multiple saved delivery addresses.
4. THE Backend SHALL validate that phone numbers conform to a valid format before saving.
5. WHEN a user requests a password change, THE Backend SHALL require the current password before accepting the new one.

---

### Requirement 20: Data Integrity and API Consistency

**User Story:** As a developer, I want the API to behave consistently and protect data integrity, so that all clients can rely on predictable responses.

#### Acceptance Criteria

1. THE Backend SHALL return all API responses in a consistent JSON envelope: `{ "success": boolean, "data": any, "error": string | null }`.
2. THE Backend SHALL validate all incoming request bodies against defined schemas and return 422 errors for invalid input.
3. THE Backend SHALL use database transactions for all multi-step operations (e.g., Order creation + payment initiation) to prevent partial writes.
4. THE Backend SHALL implement idempotency for Chapa webhook handlers so that duplicate webhook deliveries do not create duplicate payment records.
5. THE Backend SHALL log all errors with a timestamp, request ID, and stack trace to a persistent log store.
6. THE Backend SHALL return 404 for requests to non-existent resources and 403 for requests to resources the caller does not own.
