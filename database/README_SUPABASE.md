# Database Setup — Supabase

## Steps

1. Create a Supabase project at https://supabase.com
2. Go to Project Settings → Database → Connection string (URI)
3. Copy the connection string and set it as DATABASE_URL in Render environment variables
4. Open the Supabase SQL Editor and run the migration files in order:

```
database/migrations/001_initial_schema.sql
database/migrations/002_restaurants_and_menu.sql
database/migrations/003_orders_riders_ratings.sql
```

## Connection String Format
```
postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres
```

## Notes
- Supabase uses PostgreSQL — all migration files work as-is
- Enable Row Level Security (RLS) is optional since the backend handles authorization
- The backend connects via the connection pooler for better performance
