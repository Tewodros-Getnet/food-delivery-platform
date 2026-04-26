# Requirements Document

## Introduction

This feature adds a quick availability toggle to the restaurant menu management workflow. Currently, restaurant owners must open the full item edit form to change an item's `available` flag. This is slow and disruptive during busy service periods when items sell out or come back in stock frequently.

The solution has three parts:

1. **Backend**: A dedicated `PATCH /menu/:id/availability` endpoint that flips the `available` boolean in a single lightweight query, returning the updated item. The existing `PUT /menu/:id` full-update endpoint is unchanged.
2. **Restaurant app**: A `Switch` widget on each menu item card in the Menu Management screen. The toggle applies an optimistic UI update immediately and reverts if the API call fails.
3. **Customer app**: Menu items with `available: false` are visually dimmed and their "Add to Cart" button is disabled. The customer-facing API already filters unavailable items server-side; this requirement covers the client-side guard for any items that reach the UI with `available: false`.

## Glossary

- **Menu_API**: The backend Express router handling menu item endpoints, mounted at `/api/v1/menu` and `/api/v1/restaurants/:restaurantId/menu`.
- **Availability_Endpoint**: The new `PATCH /api/v1/menu/:id/availability` endpoint that toggles the `available` field of a single menu item.
- **Menu_Item**: A record in the `menu_items` table with an `available` boolean column.
- **Restaurant_Owner**: An authenticated user with the `restaurant` role who owns the restaurant that contains the menu item.
- **Restaurant_App**: The Flutter mobile application used by restaurant owners to manage their menu.
- **Customer_App**: The Flutter mobile application used by customers to browse menus and place orders.
- **Menu_Screen**: The menu management screen in the Restaurant_App that lists all menu items for a restaurant.
- **Restaurant_Detail_Screen**: The screen in the Customer_App that displays a restaurant's menu and allows customers to add items to their cart.
- **Cart**: The in-memory cart state in the Customer_App managed by `CartNotifier`.
- **Optimistic_Update**: A UI pattern where the local state is updated immediately on user action, then reverted if the corresponding API call fails.

---

## Requirements

### Requirement 1: Dedicated Availability Toggle Endpoint

**User Story:** As a restaurant owner, I want a fast, dedicated endpoint to toggle a menu item's availability, so that the operation is lightweight and does not require sending the full item payload.

#### Acceptance Criteria

1. THE Menu_API SHALL expose a `PATCH /api/v1/menu/:id/availability` endpoint that flips the `available` field of the specified Menu_Item from `true` to `false` or from `false` to `true`.
2. WHEN the Availability_Endpoint receives a valid request, THE Menu_API SHALL return HTTP 200 with the full updated Menu_Item object in the response body.
3. IF the specified Menu_Item does not exist, THEN THE Menu_API SHALL return HTTP 404.
4. IF an unauthenticated request is made to the Availability_Endpoint, THEN THE Menu_API SHALL return HTTP 401.
5. IF a user without the `restaurant` role calls the Availability_Endpoint, THEN THE Menu_API SHALL return HTTP 403.
6. IF a Restaurant_Owner calls the Availability_Endpoint for a Menu_Item that belongs to a different restaurant, THEN THE Menu_API SHALL return HTTP 403 and SHALL NOT modify the Menu_Item.
7. THE Menu_API SHALL update the `updated_at` timestamp of the Menu_Item atomically with the `available` field change.
8. FOR ALL Menu_Items, toggling availability twice SHALL return the Menu_Item to its original `available` state (round-trip property).

---

### Requirement 2: Restaurant App — Optimistic Toggle Switch

**User Story:** As a restaurant owner, I want a toggle switch directly on each menu item card, so that I can mark items as sold out or back in stock with a single tap without opening an edit form.

#### Acceptance Criteria

1. THE Menu_Screen SHALL display a `Switch` widget on each menu item card reflecting the item's current `available` state (`true` = on, `false` = off).
2. WHEN a Restaurant_Owner taps the `Switch`, THE Restaurant_App SHALL immediately update the switch visual state (Optimistic_Update) before the API call completes.
3. WHEN the Availability_Endpoint returns a success response, THE Restaurant_App SHALL update the in-memory item state with the `available` value from the response body.
4. IF the Availability_Endpoint returns an error response, THEN THE Restaurant_App SHALL revert the switch to its pre-tap state and display a `SnackBar` with the message "Failed to update availability".
5. WHILE the API call is in progress, THE Restaurant_App SHALL disable the `Switch` to prevent duplicate requests for the same item.
6. THE Menu_Screen SHALL reflect availability changes without requiring a full list reload from the server.

---

### Requirement 3: Customer App — Unavailable Item Display

**User Story:** As a customer, I want unavailable menu items to be clearly marked and non-interactive, so that I do not attempt to order items that are out of stock.

#### Acceptance Criteria

1. WHEN the Restaurant_Detail_Screen renders a Menu_Item with `available: false`, THE Customer_App SHALL display the item with reduced opacity (0.5) and a "Sold Out" label.
2. WHEN a Menu_Item has `available: false`, THE Customer_App SHALL disable the "Add to Cart" button for that item so that tapping it has no effect.
3. THE Customer_App SHALL NOT add a Menu_Item with `available: false` to the Cart, regardless of how the add action is triggered.
4. WHEN a Menu_Item has `available: true`, THE Customer_App SHALL display the item at full opacity with the "Add to Cart" button enabled, subject to the restaurant's open/closed status.
5. WHERE the customer-facing menu API returns only available items, THE Customer_App SHALL treat any Menu_Item present in the API response as available unless its `available` field is explicitly `false`.

