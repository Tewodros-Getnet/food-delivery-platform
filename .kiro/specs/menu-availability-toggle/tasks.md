# Tasks

## Task List

- [x] 1. Backend — Add PATCH Route
  - [x] 1.1 In `backend/src/routes/menu.ts`, register `menuRouter.patch('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler)` alongside the existing `PUT /:id/availability` route — no handler or service changes needed

- [ ] 2. Backend — Tests
  - [ ] 2.1 Add availability toggle test cases to `backend/src/tests/menu.test.ts` — unauthenticated returns 401, non-restaurant role returns 403, item not found returns 404, wrong restaurant owner returns 403 and does not modify the item, valid owner returns 200 with toggled `available` value and updated `updated_at`
  - [ ] 2.2 Property 1 — Toggle is a boolean flip: for any Menu_Item with mocked initial `available` state, assert `toggleAvailability` returns an item where `available === !initialAvailable`
  - [ ] 2.3 Property 2 — Double-toggle round-trip: for any Menu_Item, calling `toggleAvailability` twice returns the item to its original `available` state
  - [ ] 2.4 Property 3 — Ownership guard: for any `(itemId, ownerId)` pair where `ownerId` does not own the item's restaurant, the handler returns HTTP 403 and the DB row is not updated

- [x] 3. Restaurant App — Optimistic Toggle
  - [x] 3.1 Update `MenuService.toggleAvailability` in `mobile/restaurant/lib/features/menu/services/menu_service.dart` to use `PATCH` instead of `PUT` and return `Map<String, dynamic>` (the updated item from `res.data['data']`)
  - [x] 3.2 Add `menu` constant to `mobile/restaurant/lib/core/constants/api_constants.dart` if not already present (`static const String menu = '/menu'`)
  - [x] 3.3 Update `_MenuScreenState` in `mobile/restaurant/lib/features/menu/screens/menu_screen.dart` — add `Set<String> _togglingIds`, replace the `onChanged` callback with an optimistic update handler that: (a) immediately flips `available` in `_items`, (b) disables the Switch while in-flight, (c) updates item from server response on success, (d) reverts `available` and shows a SnackBar("Failed to update availability") on error

- [x] 4. Customer App — Unavailable Item Display
  - [x] 4.1 Update `_MenuTile` in `mobile/customer/lib/features/restaurants/screens/restaurant_detail_screen.dart` — wrap the `ListTile` in `Opacity(opacity: item.available ? 1.0 : 0.5)`, add a "Sold Out" badge overlay when `item.available` is `false`, and set `onPressed: null` on the add button when `item.available` is `false`
  - [x] 4.2 Add availability guard to `CartNotifier.addItem` in `mobile/customer/lib/features/cart/providers/cart_provider.dart` — return `false` immediately if `item.available` is `false`, before any other checks

- [ ] 5. Flutter — Tests
  - [ ] 5.1 Property 4 — Optimistic revert on error: widget test for `MenuScreen` — mock `MenuService.toggleAvailability` to throw, tap the Switch, assert the Switch value reverts to its original state and a SnackBar with "Failed to update availability" is shown
  - [ ] 5.2 Property 5 — Cart guard for unavailable items: unit test for `CartNotifier.addItem` — call with a `MenuItemModel` where `available: false`, assert return value is `false` and `cartProvider.state.items` remains empty

