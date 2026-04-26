# Design Document

## Overview

This document describes the technical design for the Menu Item Quick Availability Toggle feature. The backend already has a `toggleAvailability` service function and a `toggleAvailabilityHandler` controller. The existing route uses `PUT /:id/availability`; this feature formalises the endpoint as `PATCH /:id/availability` (adding the PATCH verb alongside the existing PUT) and completes the Flutter implementations with optimistic UI in the restaurant app and unavailable-item guards in the customer app.

---

## Architecture

The feature touches three layers with no new database schema changes required — the `available` column already exists on `menu_items`.

```
Restaurant Owner
      │  tap Switch
      ▼
Restaurant_App (optimistic update → revert on error)
      │  PATCH /api/v1/menu/:id/availability
      ▼
Menu_API (authenticate → authorize('restaurant') → ownership check → toggle)
      │  UPDATE menu_items SET available = NOT available
      ▼
PostgreSQL (menu_items.available)
      │
      ▼  (customer fetches menu)
Customer_App (dims item + disables button if available=false)
```

---

## Backend Changes

### 1. Route Addition — `menu.ts`

The existing route file already registers `PUT /:id/availability`. Add `PATCH /:id/availability` pointing to the same handler so the endpoint is accessible via the semantically correct HTTP method. The `PUT` route is kept for backward compatibility.

```typescript
// In menuRouter (mounted at /menu)
menuRouter.patch('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);
// Existing PUT kept for backward compatibility:
menuRouter.put('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);
```

### 2. Controller — `menu.controller.ts`

`toggleAvailabilityHandler` already exists and is correct. No changes needed.

```typescript
// Already implemented — shown for reference:
export async function toggleAvailabilityHandler(req, res, next) {
  const item = await menuService.getMenuItemById(req.params.id);
  if (!item) { res.status(404).json(errorResponse('Menu item not found')); return; }
  const restaurant = await restaurantService.getRestaurantById(item.restaurant_id);
  if (restaurant?.owner_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }
  const updated = await menuService.toggleAvailability(req.params.id);
  res.json(successResponse(updated));
}
```

### 3. Service — `menu.service.ts`

`toggleAvailability` already exists and is correct. No changes needed.

```typescript
// Already implemented — shown for reference:
export async function toggleAvailability(id: string): Promise<MenuItem | null> {
  const result = await query<MenuItem>(
    `UPDATE menu_items SET available = NOT available, updated_at = NOW() WHERE id = $1 RETURNING *`,
    [id]
  );
  return result.rows[0] ?? null;
}
```

### API Contract

#### `PATCH /api/v1/menu/:id/availability`

- **Auth**: JWT required (`authenticate` middleware)
- **RBAC**: `restaurant` role only (`authorize('restaurant')`)
- **Body**: None
- **Responses**:

| Status | Condition |
|---|---|
| `200` | Success — returns full updated `MenuItem` object |
| `401` | Missing or invalid JWT |
| `403` | Non-restaurant role, or item belongs to a different restaurant |
| `404` | Menu item not found |

**Response body (200)**:
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "restaurant_id": "uuid",
    "name": "Tibs",
    "description": "...",
    "price": 120.00,
    "category": "Main",
    "image_url": "https://...",
    "available": false,
    "created_at": "...",
    "updated_at": "..."
  }
}
```

---

## Flutter Changes

### Restaurant App

#### Updated: `MenuScreen` (`menu_screen.dart`)

The current implementation calls `_load()` (full server reload) after every toggle. Replace this with an Optimistic_Update pattern:

1. Immediately flip the item's `available` value in `_items` list state.
2. Disable the `Switch` for that item while the API call is in progress.
3. On success, update the item with the server-returned value.
4. On error, revert the `available` value and show a `SnackBar`.

**State tracking**: Add a `Set<String> _togglingIds` to track which item IDs have an in-flight toggle request.

```dart
// Pseudocode for the updated toggle handler:
Future<void> _toggleAvailability(int index) async {
  final item = _items[index] as Map<String, dynamic>;
  final id = item['id'] as String;
  final originalValue = item['available'] as bool? ?? true;

  // Optimistic update
  setState(() {
    _togglingIds.add(id);
    (_items[index] as Map<String, dynamic>)['available'] = !originalValue;
  });

  try {
    final updated = await ref.read(menuServiceProvider).toggleAvailability(id);
    setState(() {
      _items[index] = updated; // use server-returned value
    });
  } catch (_) {
    // Revert
    setState(() {
      (_items[index] as Map<String, dynamic>)['available'] = originalValue;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update availability')),
      );
    }
  } finally {
    setState(() => _togglingIds.remove(id));
  }
}
```

**Switch widget** (updated):
```dart
Switch(
  value: item['available'] as bool? ?? true,
  activeColor: const Color(0xFF2E7D32),
  onChanged: _togglingIds.contains(item['id'])
      ? null  // disabled while in-flight
      : (_) => _toggleAvailability(i),
),
```

#### Updated: `MenuService` (`menu_service.dart`)

Update `toggleAvailability` to use `PATCH` and return the updated item map:

```dart
Future<Map<String, dynamic>> toggleAvailability(String id) async {
  final res = await _client.dio.patch('${ApiConstants.menu}/$id/availability');
  return res.data['data'] as Map<String, dynamic>;
}
```

#### `ApiConstants` addition (restaurant app)

The restaurant app needs a `menu` constant. Check `api_constants.dart` in the restaurant app and add if missing:

```dart
static const String menu = '/menu';
```

### Customer App

#### Updated: `_MenuTile` widget (`restaurant_detail_screen.dart`)

Wrap the `ListTile` in an `Opacity` widget and conditionally disable the add button based on `item.available`:

```dart
class _MenuTile extends ConsumerWidget {
  // ...
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.available;
    final canAdd = isRestaurantOpen && isAvailable;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: ListTile(
        // ... existing content unchanged ...
        trailing: Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              icon: Icon(Icons.add_circle,
                  color: canAdd ? Colors.orange : Colors.grey, size: 32),
              onPressed: canAdd ? () { /* existing add logic */ } : null,
            ),
            if (!isAvailable)
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Sold Out',
                      style: TextStyle(color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

#### Cart guard — `CartNotifier` (`cart_provider.dart`)

Add an availability check in `addItem` as a defence-in-depth guard:

```dart
bool addItem(MenuItemModel item, String restaurantId) {
  if (!item.available) return false;  // NEW guard
  if (state.restaurantId != null && state.restaurantId != restaurantId)
    return false;
  // ... rest unchanged ...
}
```

---

## Correctness Properties

### Property 1: Toggle is a boolean flip

For any Menu_Item with any initial `available` state, calling `toggleAvailability` must return an item where `available` is the logical negation of the input item's `available` value.

- **Pattern**: Invariant — the result is always `!input.available`.
- **Test type**: Property-based test (fast-check) — vary item ID and initial `available` state with a mocked DB query.

### Property 2: Double-toggle round-trip

For any Menu_Item, toggling availability twice must return the item to its original `available` state.

- **Pattern**: Round-trip — `toggle(toggle(item)).available === item.available`.
- **Test type**: Property-based test — vary item data and initial state.

### Property 3: Ownership guard is enforced for all items

For any combination of `(itemId, requestingOwnerId)` where `requestingOwnerId` does not own the restaurant containing `itemId`, the handler must return HTTP 403 and the `available` field must remain unchanged.

- **Pattern**: Invariant — authorization is always enforced regardless of item data.
- **Test type**: Property-based test — vary item IDs and owner IDs to ensure mismatch always produces 403.

### Property 4: Optimistic update reverts on any error (example-based)

When the `toggleAvailability` API call throws an error, the `Switch` value in the Restaurant_App must revert to its pre-tap state.

- **Pattern**: Error condition — revert on failure.
- **Test type**: Widget test with mocked service returning an error.

### Property 5: Unavailable items cannot be added to cart (example-based)

When `item.available` is `false`, calling `CartNotifier.addItem` must return `false` and the cart state must remain unchanged.

- **Pattern**: Invariant — cart guard is always enforced.
- **Test type**: Unit test with `available: false` item.

