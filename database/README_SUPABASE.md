# Database Setup — Supabase

## Steps

1. Create a Supabase project at https://supabase.com
2. Go to Project Settings → Database → Connection string (URI)
3. Copy the connection string and set it as DATABASE_URL in Render environment variables
4. Open the Supabase SQL Editor and run the migration files **in order**:

```
database/migrations/001_initial_schema.sql
database/migrations/002_restaurants_and_menu.sql
database/migrations/003_orders_riders_ratings.sql
database/migrations/004_inconsistencies_fix.sql
database/migrations/005_restaurant_riders.sql
database/migrations/006_email_verification.sql
```

## Connection String Format
```
postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres
```

## Migration Notes

| File | What it adds |
|------|-------------|
| 001 | Users, refresh tokens |
| 002 | Restaurants, menu items, addresses |
| 003 | Orders, riders, ratings, disputes, FCM tokens |
| 004 | is_open/operating_hours on restaurants, estimated_delivery_time on orders, rider_profiles table |
| 005 | restaurant_riders table (exclusive rider assignment), rider_invitations table |
| 006 | email_verified on users, verification_codes table (OTP) |

## Notes
- Supabase uses PostgreSQL — all migration files work as-is
- Enable Row Level Security (RLS) is optional since the backend handles authorization
- The backend connects via the connection pooler for better performance
