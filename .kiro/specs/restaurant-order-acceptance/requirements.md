# Requirements Document

## Introduction

This feature introduces an explicit accept/reject step into the order lifecycle for the food delivery platform. Currently, when a customer's payment succeeds, the order transitions directly to `confirmed` status and the restaurant begins preparing it without any acknowledgement. This creates a risk of restaurants receiving orders they cannot fulfill, leading to poor customer experience and wasted preparation time.

The new flow inserts a `pending_acceptance` status between payment success and `confirmed`. After payment, the restaurant receives a real-time notification and has a configurable time window (default: 3 minutes) to explicitly accept or reject the order. If the restaurant accepts, the order moves to `confirmed` and the existing flow continues unchanged. If the restaurant rejects, or if no response is received within the timeout window, the order is cancelled and a full refund is initiated automatically.

This feature touches the backend (Node.js/Express/TypeScript), the restaurant Flutter app, the customer Flutter app, and the PostgreSQL database schema.

## Glossary

- **Order_Service**: The backend Node.js/Express service responsible for order lifecycle management.
- **Acceptance_API**: The new `PUT /orders/:id/accept` and `PUT /orders/:id/reject` endpoints added to the Order_Service.
- **Scheduler_Service**: The existing cron-based backend service extended to handle acceptance timeout jobs.
- **Refund_Service**: The existing service that initiates refunds via the Chapa payment gateway.
- **Notification_Service**: The combined Socket.IO and FCM push notification infrastructure used to alert users of order status changes.
- **Restaurant_App**: The Flutter mobile application used by restaurant owners to manage orders.
- **Customer_App**: The Flutter mobile application used by customers to place and track orders.
- **Restaurant_Owner**: An authenticated user with the `restaurant` role who owns the restaurant associated with the order.
- **Customer**: An authenticated user with the `customer` role who placed the order.
- **Pending_Acceptance_Status**: The new `pending_acceptance` order status that an order enters immediately after successful payment, before the restaurant has responded.
- **Acceptance_Window**: The configurable time period (default: 3 minutes) during which the restaurant must accept or reject an order in `pending_acceptance` status.
- **Platform_Config**: The existing `platform_config` database table used to store configurable platform parameters.

---

## Requirements

### Requirement 1: New Order Status — `pending_acceptance`

**User Story:** As a platform operator, I want a distinct order status between payment and confirmation, so that the restaurant's explicit acknowledgement is captured before preparation begins.

#### Acceptance Criteria

1. THE Order_Service SHALL add `pending_acceptance` as a valid value in the `status` column constraint of the `orders` table.
2. WHEN a Chapa webhook delivers a successful payment event for an order in `pending_payment` status, THE Order_Service SHALL transition the order status to `pending_acceptance` instead of `confirmed`.
3. THE Order_Service SHALL record the timestamp at which the order entered `pending_acceptance` status in a new `acceptance_deadline` column on the `orders` table, set to `NOW() + acceptance_window_interval`.
4. THE Platform_Config SHALL store the acceptance window duration under the key `order_acceptance_timeout_seconds` with a default value of `180` (3 minutes).
5. IF an order is in any status other than `pending_acceptance`, THEN THE Acceptance_API SHALL reject accept and reject requests with HTTP 409.

---

### Requirement 2: Restaurant Accept Endpoint

**User Story:** As a restaurant owner, I want to accept an incoming order, so that the customer knows their order is being prepared and the kitchen can begin work.

#### Acceptance Criteria

1. WHEN a Restaurant_Owner sends an accept request for an order in `pending_acceptance` status that belongs to their restaurant, THE Acceptance_API SHALL transition the order status to `confirmed` and return HTTP 200 with the updated order object.
2. WHEN an order is accepted, THE Acceptance_API SHALL optionally record an `estimated_prep_time_minutes` value provided in the request body, if present.
3. IF a Restaurant_Owner sends an accept request for an order that belongs to a different restaurant, THEN THE Acceptance_API SHALL return HTTP 403.
4. IF an unauthenticated user calls the accept endpoint, THEN THE Acceptance_API SHALL return HTTP 401.
5. IF a user with a non-restaurant role calls the accept endpoint, THEN THE Acceptance_API SHALL return HTTP 403.
6. WHEN an order is successfully accepted, THE Notification_Service SHALL emit an `order:status_changed` socket event to the Customer and send an FCM push notification with the title "Order Accepted" to the Customer.

---

### Requirement 3: Restaurant Reject Endpoint

**User Story:** As a restaurant owner, I want to reject an incoming order I cannot fulfill, so that the customer is notified promptly and receives a refund.

#### Acceptance Criteria

1. WHEN a Restaurant_Owner sends a reject request with a non-empty reason for an order in `pending_acceptance` status that belongs to their restaurant, THE Acceptance_API SHALL transition the order status to `cancelled`, record `cancelled_by = 'restaurant'`, record the rejection reason in `cancellation_reason`, and return HTTP 200 with the updated order object.
2. IF a Restaurant_Owner sends a reject request without a reason or with a blank reason, THEN THE Acceptance_API SHALL return HTTP 422 with a validation error.
3. IF a Restaurant_Owner sends a reject request for an order that belongs to a different restaurant, THEN THE Acceptance_API SHALL return HTTP 403.
4. WHEN an order is successfully rejected, THE Order_Service SHALL invoke the Refund_Service to initiate a full refund for the order amount (fire-and-forget).
5. WHEN an order is successfully rejected, THE Notification_Service SHALL emit an `order:status_changed` socket event to the Customer and send an FCM push notification with the title "Order Rejected" and a body that includes the rejection reason.
6. IF the Refund_Service fails after all retries, THEN THE Refund_Service SHALL log the failure with the order ID and error details without throwing an unhandled exception to the caller.
7. IF the FCM push notification fails to deliver, THEN THE Notification_Service SHALL log the failure and continue without blocking the rejection response.

---

### Requirement 4: Acceptance Timeout — Auto-Cancel

**User Story:** As a customer, I want my order to be automatically cancelled and refunded if the restaurant does not respond within the acceptance window, so that I am not left waiting indefinitely.

#### Acceptance Criteria

1. THE Scheduler_Service SHALL run a periodic job (every 60 seconds) that queries for all orders in `pending_acceptance` status where `acceptance_deadline < NOW()`.
2. WHEN the Scheduler_Service identifies an expired `pending_acceptance` order, THE Order_Service SHALL transition the order status to `cancelled`, set `cancellation_reason` to `'Restaurant did not respond in time'`, and set `cancelled_by` to `'restaurant'`.
3. WHEN an order is auto-cancelled due to timeout, THE Order_Service SHALL invoke the Refund_Service to initiate a full refund (fire-and-forget).
4. WHEN an order is auto-cancelled due to timeout, THE Notification_Service SHALL send an FCM push notification to the Customer with the title "Order Cancelled" and a body stating the restaurant did not respond in time.
5. WHEN an order is auto-cancelled due to timeout, THE Notification_Service SHALL send an FCM push notification to the Restaurant_Owner with the title "Order Expired" and a body stating the acceptance window elapsed.
6. IF the Scheduler_Service job encounters a database error, THEN THE Scheduler_Service SHALL log the error and continue without crashing the process.
7. WHEN an order is auto-cancelled due to timeout, THE Notification_Service SHALL emit an `order:status_changed` socket event to the Customer.

---

### Requirement 5: Restaurant App — Incoming Order Screen

**User Story:** As a restaurant owner, I want to see incoming orders requiring my action prominently in the app, so that I can respond within the acceptance window.

#### Acceptance Criteria

1. WHEN an order enters `pending_acceptance` status, THE Restaurant_App SHALL display the order in a dedicated "New Orders" section at the top of the orders screen, visually distinct from confirmed orders.
2. WHILE an order is in `pending_acceptance` status, THE Restaurant_App SHALL display a countdown timer showing the remaining time in the Acceptance_Window.
3. WHILE an order is in `pending_acceptance` status, THE Restaurant_App SHALL display an "Accept" button and a "Reject" button on the order card.
4. WHEN a Restaurant_Owner taps the "Accept" button, THE Restaurant_App SHALL call the accept endpoint and display a loading indicator until a response is received.
5. WHEN a Restaurant_Owner taps the "Reject" button, THE Restaurant_App SHALL present a dialog requiring the owner to enter a rejection reason before submitting.
6. WHEN the accept endpoint returns a success response, THE Restaurant_App SHALL move the order from the "New Orders" section to the active orders list and display a success message.
7. WHEN the reject endpoint returns a success response, THE Restaurant_App SHALL remove the order from the "New Orders" section and display a confirmation message.
8. IF the accept or reject endpoint returns an error response, THEN THE Restaurant_App SHALL display the error message and leave the order card in its current state.
9. WHEN the countdown timer reaches zero, THE Restaurant_App SHALL visually indicate the order has expired and remove it from the "New Orders" section upon receiving the `order:status_changed` socket event.

---

### Requirement 6: Customer App — Waiting for Acceptance Screen

**User Story:** As a customer, I want to see that my order is waiting for the restaurant's confirmation, so that I understand the order is not yet being prepared.

#### Acceptance Criteria

1. WHEN an order transitions to `pending_acceptance` status, THE Customer_App SHALL display a "Waiting for restaurant confirmation" status message on the order tracking screen.
2. WHILE an order is in `pending_acceptance` status, THE Customer_App SHALL display a progress indicator communicating that the restaurant is reviewing the order.
3. WHEN the Customer_App receives an `order:status_changed` socket event transitioning the order to `confirmed`, THE Customer_App SHALL update the tracking screen to the standard "Order Confirmed" state without requiring a manual refresh.
4. WHEN the Customer_App receives an `order:status_changed` socket event transitioning the order to `cancelled` from `pending_acceptance`, THE Customer_App SHALL display a notification stating the order was not accepted and that a refund has been initiated.
5. IF the Customer_App is not connected via socket when the status changes, THE Customer_App SHALL reflect the correct status upon the next successful API poll or socket reconnection.

---

### Requirement 7: Notification Delivery Guarantees

**User Story:** As a customer or restaurant owner, I want to receive status change notifications even if I am temporarily offline, so that I do not miss critical order updates.

#### Acceptance Criteria

1. WHEN the Notification_Service emits an `order:status_changed` event and the target user is not connected via socket, THE Notification_Service SHALL queue the event using the existing missed-event queue mechanism for delivery upon reconnection, within the 5-minute TTL.
2. THE Notification_Service SHALL send FCM push notifications for all `pending_acceptance` → `confirmed`, `pending_acceptance` → `cancelled` (reject), and `pending_acceptance` → `cancelled` (timeout) transitions to both the affected Customer and the Restaurant_Owner as applicable.
3. IF an FCM token is invalid or unregistered, THEN THE Notification_Service SHALL remove the token from the `fcm_tokens` table and continue without retrying on that token.
