# Tasks

## Task List

- [x] 1. Backend — Operating Hours Endpoint
  - [x] 1.1 Add `PUT /restaurants/my/hours` route in `backend/src/routes/restaurants.ts` — validates body shape (object with day keys, each having `open`/`close` HH:MM strings or `closed: true`), updates `operating_hours` JSONB column
  - [x] 1.2 Add `updateOperatingHours(ownerId, hours)` function in `backend/src/services/restaurant.service.ts`

- [x] 2. Backend — Auto Open/Close Scheduler Job
  - [x] 2.1 Add `startOperatingHoursJob()` in `backend/src/services/scheduler.service.ts` — runs every minute, checks current Addis Ababa time (UTC+3) against each restaurant's `operating_hours`, updates `is_open` only for restaurants with non-null `operating_hours`
  - [x] 2.2 Register `startOperatingHoursJob()` in `backend/src/index.ts`

- [-] 3. Restaurant App — Operating Hours Screen
  - [x] 3.1 Create `mobile/restaurant/lib/features/restaurant/screens/operating_hours_screen.dart` — 7-day list, each row has day name, open/closed toggle, and time pickers for open/close times; Save button calls `PUT /restaurants/my/hours`
  - [x] 3.2 Add `/hours` route in `mobile/restaurant/lib/core/router/app_router.dart`
  - [x] 3.3 Add "Operating Hours" `ListTile` entry in `mobile/restaurant/lib/features/profile/screens/profile_screen.dart` that navigates to `/hours`

- [x] 4. Customer App — Display Operating Hours
  - [x] 4.1 Add `operatingHours` field to `RestaurantModel` in `mobile/customer/lib/features/restaurants/models/restaurant_model.dart`
  - [x] 4.2 Add operating hours section to `RestaurantDetailScreen` in `mobile/customer/lib/features/restaurants/screens/restaurant_detail_screen.dart` — shows today's hours prominently and a collapsible full weekly schedule
