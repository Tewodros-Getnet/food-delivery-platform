# Requirements Document

## Introduction

This feature enables restaurant owners to cancel orders they cannot fulfill — for example, due to a missing ingredient or a kitchen issue. Currently, only customers and admins can cancel orders. Restaurants need a self-service cancellation path that triggers a customer refund and notifies the customer in real time, without requiring admin intervention.

The cancellation window closes once a rider has physically picked up the food (i.e., once the order reaches `picked_up` status). Cancellations are allowed for orders in `confirmed` or `ready_for_pickup` status. The existing refund service (Chapa) and notification infrastructure (Socket.IO + FCM) are reused.

## Glossary

- **Order_Service**: The backend Node.js/Express service responsible for order lifecycle management.
- **Restaurant_App**: The Flutter mobile application used by restaurant owners to manage orders.
- **Cancellation_API**: The new `PUT /orders/:id/restaurant-cancel` endpoint added to the Order_Service.
- **Refund_Service**: The existing service that initiates refunds via the Chapa payment gateway.
- **Notification_Service**: The combined Socket.IO and FCM push notification infrastructure used to alert users of order status changes.
- **Restaurant_Owner**: An authenticated user with the `restaurant` role who owns the restaurant associated with the order.
- **Cancellable_Status**: An order status from which restaurant cancellation is permitted — either `confirmed` or `ready_for_pickup`.
- **Non-Cancellable_Status**: An order status from which restaurant cancellation is not permitted — `picked_up`, `delivered`, `cancelled`, `pending_payment`, or `payment_failed`.

---

## Requirements

### Requirement 1: Restaurant Cancellation Endpoint

**User Story:** As a restaurant owner, I want to cancel an order I cannot fulfill via the app, so that the customer is promptly notified and refunded without requiring admin involvement.

#### Acceptance Criteria

1. WHEN a Restaurant_Owner sends a cancellation request for an order in a Cancellable_Status, THE Cancellation_API SHALL update the order status to `cancelled` and record the provided cancellation reason.
2. WHEN a Restaurant_Owner sends a cancellation request, THE Cancellation_API SHALL verify that the order belongs to the restaurant owned by the requesting Restaurant_Owner before processing the cancellation.
3. IF a Restaurant_Owner sends a cancellation request for an order in a Non-Cancellable_Status, THEN THE Cancellation_API SHALL return HTTP 409 with a descriptive error message indicating the order cannot be cancelled in its current status.
4. IF a Restaurant_Owner sends a cancellation request for an order that belongs to a different restaurant, THEN THE Cancellation_API SHALL return HTTP 403.
5. IF an unauthenticated or non-restaurant-role user calls the Cancellation_API, THEN THE Cancellation_API SHALL return HTTP 401 or HTTP 403 respectively.
6. WHEN a cancellation is successfully recorded, THE Cancellation_API SHALL return HTTP 200 with the updated order object.

---

### Requirement 2: Refund Initiation on Restaurant Cancellation

**User Story:** As a customer, I want to receive a full refund when a restaurant cancels my order, so that I am not charged for food I will not receive.

#### Acceptance Criteria

1. WHEN an order is successfully cancelled by a Restaurant_Owner, THE Order_Service SHALL invoke the Refund_Service to initiate a full refund for the order amount.
2. WHILE the Refund_Service is processing a refund, THE Order_Service SHALL continue and return a response to the caller without waiting for the refund to complete (fire-and-forget).
3. IF the Refund_Service fails to initiate a refund after all retries, THEN THE Refund_Service SHALL log the failure with the order ID and error details without throwing an unhandled exception to the caller.

---

### Requirement 3: Customer Notification on Restaurant Cancellation

**User Story:** As a customer, I want to be notified immediately when a restaurant cancels my order, so that I can place a new order elsewhere.

#### Acceptance Criteria

1. WHEN an order is successfully cancelled by a Restaurant_Owner, THE Notification_Service SHALL emit an `order:status_changed` socket event to the customer's connected session.
2. WHEN an order is successfully cancelled by a Restaurant_Owner, THE Notification_Service SHALL send an FCM push notification to the customer with the title "Order Cancelled" and a body that includes the cancellation reason.
3. IF the customer is not connected via socket at the time of cancellation, THEN THE Notification_Service SHALL queue the `order:status_changed` event for delivery when the customer reconnects, within the 5-minute missed-event TTL.
4. IF the FCM push notification fails to deliver, THEN THE Notification_Service SHALL log the failure and continue without blocking the cancellation response.

---

### Requirement 4: Cancel Button in Restaurant App

**User Story:** As a restaurant owner, I want a cancel button on the order card in the orders screen, so that I can cancel an unfulfillable order directly from the app.

#### Acceptance Criteria

1. WHILE an order is in `confirmed` or `ready_for_pickup` status, THE Restaurant_App SHALL display a "Cancel Order" button on the order card in the orders screen.
2. WHEN a Restaurant_Owner taps the "Cancel Order" button, THE Restaurant_App SHALL present a confirmation dialog requiring the owner to provide a cancellation reason before submitting.
3. WHEN the Restaurant_Owner confirms the cancellation with a reason, THE Restaurant_App SHALL call the Cancellation_API and display a loading indicator until a response is received.
4. WHEN the Cancellation_API returns a success response, THE Restaurant_App SHALL remove the order from the active orders list and display a success message.
5. IF the Cancellation_API returns an error response, THEN THE Restaurant_App SHALL display the error message to the Restaurant_Owner and leave the order card in its current state.
6. WHILE an order is in `rider_assigned` or `picked_up` status, THE Restaurant_App SHALL NOT display the "Cancel Order" button on the order card.

---

### Requirement 5: Cancellation Reason

**User Story:** As an admin, I want to know why a restaurant cancelled an order, so that I can monitor patterns and identify problematic restaurants.

#### Acceptance Criteria

1. WHEN a Restaurant_Owner submits a cancellation, THE Cancellation_API SHALL accept a non-empty `reason` string in the request body.
2. IF a Restaurant_Owner submits a cancellation without a reason, THEN THE Cancellation_API SHALL return HTTP 422 with a validation error indicating the reason is required.
3. THE Order_Service SHALL persist the cancellation reason in the `cancellation_reason` column of the orders table alongside the `cancelled_at` timestamp.
