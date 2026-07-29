# Implementation Plan: Food Delivery Platform

## Overview

This implementation plan breaks down the food delivery platform into discrete, actionable coding tasks. The platform consists of a Node.js + Express backend with PostgreSQL, three Flutter mobile apps (Customer, Restaurant, Rider), and a Next.js admin dashboard. The implementation follows a phased approach: backend foundation, authentication, core features, real-time communication, external integrations, frontend clients, and testing.

Each task references specific requirements and design sections. Property-based tests validate the 73 correctness properties defined in the design document. Tasks marked with `*` are optional and can be skipped for faster MVP delivery.

## Tasks

- [x] 1. Backend Project Setup and Database Schema
  - [x] 1.1 Initialize Node.js project with Express, TypeScript, and essential dependencies
    - Create package.json with express, pg, socket.io, jsonwebtoken, bcrypt, express-validator
    - Set up TypeScript configuration with strict mode
    - Create project structure: src/routes, src/controllers, src/middleware, src/models, src/services, src/utils
    - Configure environment variables with dotenv
    - _Requirements: 20.1, 20.2_

  - [x] 1.2 Set up PostgreSQL database connection and migration system
    - Install node-pg-migrate for database migrations
    - Create database connection pool with pg
    - Write initial migration for all core tables (users, refresh_tokens, restaurants, menu_items, addresses, orders, order_items, rider_locations, ratings, disputes, platform_config, fcm_tokens)
    - Add indexes as defined in design document
    - _Requirements: 20.3_

  - [x] 1.3 Write property tests for database schema constraints
    - **Property 70: Multi-step operations use transactions**
    - **Validates: Requirements 20.3**

- [x] 2. Authentication and Authorization Module
  - [x] 2.1 Implement user registration endpoint with password hashing
    - Create POST /auth/register endpoint accepting email, password, role
    - Hash password with bcrypt (cost factor 10)
    - Generate JWT (15min expiry) and refresh token (7d expiry)
    - Store refresh token hash in database
    - Return consistent JSON envelope with tokens and user data
    - _Requirements: 1.1, 1.2, 20.1_

  - [x] 2.2 Write property tests for registration
    - **Property 1: Registration creates account with hashed password and tokens**
    - **Property 2: Duplicate email registration rejected**
    - **Validates: Requirements 1.2, 1.3**

  - [x] 2.3 Implement login endpoint with credential validation
    - Create POST /auth/login endpoint accepting email and password
    - Verify password with bcrypt.compare
    - Generate new JWT and refresh token on success
    - Return 401 for invalid credentials
    - _Requirements: 1.4, 1.5_

  - [x] 2.4 Write property tests for login
    - **Property 3: Login with valid credentials returns tokens**
    - **Property 4: Login with invalid credentials rejected**
    - **Validates: Requirements 1.4, 1.5**

  - [x] 2.5 Implement JWT refresh endpoint
    - Create POST /auth/refresh endpoint accepting refresh token
    - Verify refresh token hash exists and not expired
    - Generate new JWT without requiring password
    - Return 401 for invalid/expired tokens
    - _Requirements: 1.6, 1.7_

  - [x] 2.6 Write property tests for token refresh
    - **Property 5: Refresh token exchange issues new JWT**
    - **Property 6: Invalid refresh token rejected**
    - **Validates: Requirements 1.6, 1.7**

  - [x] 2.7 Implement logout endpoint with token invalidation
    - Create POST /auth/logout endpoint
    - Delete refresh token from database
    - Return success response
    - _Requirements: 1.9_

  - [x] 2.8 Write property test for logout
    - **Property 7: Logout invalidates refresh token**
    - **Validates: Requirements 1.9**

  - [x] 2.9 Create authentication middleware for JWT verification
    - Extract JWT from Authorization header
    - Verify JWT signature and expiry
    - Attach decoded user data to request object
    - Return 401 for missing/invalid JWT
    - _Requirements: 1.10_

  - [x] 2.10 Create role-based access control (RBAC) middleware
    - Accept allowed roles as parameter
    - Check authenticated user's role against allowed roles
    - Return 403 for unauthorized roles
    - _Requirements: 1.10_

  - [x] 2.11 Write property test for RBAC
    - **Property 8: Role-based access control enforced**
    - **Validates: Requirements 1.10**

- [x] 3. Restaurant Management Module
  - [x] 3.1 Implement restaurant registration endpoint
    - Create POST /restaurants endpoint (restaurant role only)
    - Accept name, description, address, latitude, longitude
    - Set initial status to 'pending'
    - Store restaurant record in database
    - _Requirements: 2.1, 2.7_

  - [x] 3.2 Write property tests for restaurant registration
    - **Property 9: Restaurant registration starts in pending status**
    - **Property 14: Incomplete restaurant data rejected**
    - **Validates: Requirements 2.1, 2.7**

  - [x] 3.3 Implement Cloudinary integration for restaurant images
    - Install cloudinary SDK
    - Create utility function for image upload
    - Add logo_url and cover_image_url fields to restaurant creation
    - Store Cloudinary URLs in database
    - _Requirements: 2.5, 2.6_

  - [x] 3.4 Write property test for image URL storage
    - **Property 13: Image URLs stored in restaurant record**
    - **Validates: Requirements 2.6**

  - [x] 3.5 Implement restaurant approval/rejection endpoints (admin only)
    - Create POST /restaurants/:id/approve endpoint
    - Create POST /restaurants/:id/reject endpoint
    - Update restaurant status accordingly
    - Apply RBAC middleware for admin role
    - _Requirements: 2.3, 2.4_

  - [x] 3.6 Write property tests for restaurant approval
    - **Property 11: Restaurant approval makes it visible to customers**
    - **Property 12: Restaurant rejection updates status**
    - **Validates: Requirements 2.3, 2.4**

  - [x] 3.7 Implement restaurant listing endpoints
    - Create GET /restaurants endpoint (customer-facing, approved only)
    - Create GET /restaurants/:id endpoint for details
    - Add pagination support (default 20 per page)
    - Add category filter support
    - _Requirements: 4.1, 4.2, 4.4_

  - [x] 3.8 Write property test for customer listings
    - **Property 21: Customer listings show only approved restaurants**
    - **Validates: Requirements 4.1**

  - [x] 3.9 Implement restaurant suspension endpoint (admin only)
    - Create PUT /restaurants/:id/suspend endpoint
    - Update restaurant status to 'suspended'
    - Hide from customer listings
    - Cancel active orders from suspended restaurant
    - _Requirements: 11.3, 11.4_

  - [x] 3.10 Write property test for restaurant suspension
    - **Property 48: Suspended restaurant hidden and orders cancelled**
    - **Validates: Requirements 11.4**

- [x] 4. Menu Management Module
  - [x] 4.1 Implement menu item creation endpoint
    - Create POST /restaurants/:id/menu endpoint (restaurant owner only)
    - Require name, description, price, category, image
    - Verify restaurant is approved before allowing menu creation
    - Upload image to Cloudinary and store URL
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 4.2 Write property tests for menu item creation
    - **Property 10: Pending restaurants cannot publish menu items**
    - **Property 15: Menu item creation requires all fields**
    - **Property 16: Menu item image URL stored**
    - **Validates: Requirements 2.2, 3.2, 3.3**

  - [x] 4.3 Implement menu item update and delete endpoints
    - Create PUT /menu/:id endpoint for updates
    - Create DELETE /menu/:id endpoint
    - Verify ownership before allowing modifications
    - For delete: mark as unavailable if in active orders, else delete
    - _Requirements: 3.1, 3.7_

  - [x] 4.4 Write property test for menu item deletion
    - **Property 20: Deleting menu item in active order marks unavailable**
    - **Validates: Requirements 3.7**

  - [x] 4.5 Implement menu item availability toggle
    - Create PUT /menu/:id/availability endpoint
    - Toggle available field between true/false
    - _Requirements: 3.4_

  - [x] 4.6 Write property test for availability toggle
    - **Property 17: Menu item availability toggle**
    - **Validates: Requirements 3.4**

  - [x] 4.7 Implement menu listing endpoint with filters
    - Create GET /restaurants/:id/menu endpoint
    - Filter out unavailable items for customer queries
    - Support category filtering
    - _Requirements: 3.5, 3.6_

  - [x] 4.8 Write property tests for menu listings
    - **Property 18: Unavailable menu items excluded from customer queries**
    - **Property 19: Menu items grouped by category**
    - **Validates: Requirements 3.5, 3.6**

- [x] 5. Search and Discovery Module
  - [x] 5.1 Implement restaurant and menu search endpoint
    - Create GET /search endpoint with query parameter
    - Search restaurant names and descriptions (case-insensitive)
    - Search menu item names and descriptions (case-insensitive)
    - Return paginated results
    - _Requirements: 4.3, 4.4_

  - [x] 5.2 Write property tests for search
    - **Property 23: Search query matches case-insensitively**
    - **Property 24: Listing endpoints return paginated results**
    - **Validates: Requirements 4.3, 4.4**

- [x] 6. Delivery Fee Calculation Module
  - [x] 6.1 Implement Haversine distance calculation utility
    - Create utility function using Haversine formula
    - Accept two coordinate pairs (lat, lon)
    - Return distance in kilometers
    - _Requirements: 16.3_

  - [x] 6.2 Write property test for distance calculation
    - **Property 57: Distance calculated using Haversine formula**
    - **Validates: Requirements 16.3**

  - [x] 6.3 Implement delivery fee calculation utility
    - Create function accepting restaurant coords, customer coords, config
    - Calculate distance using Haversine
    - Apply formula: base_fee + (distance_km × rate_per_km)
    - Round to 2 decimal places
    - _Requirements: 16.1_

  - [x] 6.4 Write property test for fee calculation
    - **Property 56: Delivery fee calculated correctly**
    - **Validates: Requirements 16.1**

  - [x] 6.5 Implement fee estimation endpoint
    - Create GET /payments/estimate-fee endpoint
    - Accept restaurant_id and delivery_address_id
    - Fetch coordinates from database
    - Return estimated fee
    - _Requirements: 16.4_

- [x] 7. Order Creation and Payment Module
  - [x] 7.1 Implement order creation endpoint with cart validation
    - Create POST /orders endpoint (customer role only)
    - Accept cart items, restaurant_id, delivery_address_id
    - Validate all menu items are available
    - Calculate subtotal from current menu prices
    - Calculate delivery fee using utility function
    - Create order with status 'pending_payment'
    - Use database transaction for atomicity
    - _Requirements: 5.5, 6.1, 20.3_

  - [x] 7.2 Write property tests for order creation
    - **Property 25: Checkout validates item availability**
    - **Property 26: Order creation starts in pending_payment**
    - **Validates: Requirements 5.5, 6.1**

  - [x] 7.3 Integrate Chapa payment gateway
    - Install Chapa SDK or create HTTP client for Chapa API
    - Implement payment session initialization
    - Generate payment reference (UUID)
    - Return payment URL to client
    - _Requirements: 6.2_

  - [x] 7.4 Write property test for payment initiation
    - **Property 27: Order creation returns payment URL**
    - **Validates: Requirements 6.2**

  - [x] 7.5 Implement Chapa webhook handler with signature verification
    - Create POST /payments/webhook endpoint (no auth required)
    - Verify Chapa webhook signature
    - Extract payment reference and status
    - Implement idempotency check using payment reference
    - Update order status based on payment result
    - Store payment details (reference, amount, timestamp)
    - Use database transaction
    - _Requirements: 6.3, 6.4, 6.5, 6.6, 20.4_

  - [x] 7.6 Write property tests for webhook handling
    - **Property 28: Successful payment webhook updates order to confirmed**
    - **Property 29: Failed payment webhook updates order to payment_failed**
    - **Property 30: Invalid webhook signature rejected**
    - **Property 31: Confirmed order stores payment details**
    - **Property 71: Webhook idempotency prevents duplicates**
    - **Validates: Requirements 6.3, 6.4, 6.5, 6.6, 20.4**

  - [x] 7.7 Implement payment session expiry handling
    - Create scheduled job or cron to check expired payments
    - Update orders with expired payment sessions to 'payment_failed'
    - _Requirements: 6.8_

  - [x] 7.8 Write property test for payment expiry
    - **Property 32: Expired payment session marks order failed**
    - **Validates: Requirements 6.8**

- [x] 8. WebSocket Real-Time Communication Module
  - [x] 8.1 Set up Socket.io server with JWT authentication
    - Install socket.io
    - Create WebSocket server attached to Express
    - Implement JWT authentication middleware for socket connections
    - Create room management for users (join room by user_id)
    - _Requirements: 7.1, 9.1_

  - [x] 8.2 Implement order status change WebSocket notifications
    - Create utility function to emit 'order:status_changed' event
    - Send to customer room on every order status transition
    - Send to restaurant room when order becomes 'confirmed'
    - Include full order details in event payload
    - _Requirements: 7.1, 9.1_

  - [x] 8.3 Write property tests for WebSocket notifications
    - **Property 33: Confirmed order triggers restaurant WebSocket notification**
    - **Property 43: Order status transitions trigger customer WebSocket notifications**
    - **Validates: Requirements 7.1, 9.1**

  - [x] 8.4 Implement rider location broadcast
    - Create utility function to emit 'rider:location_update' event
    - Send to customer room when order status is 'picked_up'
    - Include rider_id, order_id, coordinates, timestamp
    - _Requirements: 9.4, 9.6_

  - [x] 8.5 Write property test for rider location broadcast
    - **Property 44: Rider location updates broadcast to customer**
    - **Validates: Requirements 9.6**

  - [x] 8.6 Implement delivery request WebSocket event
    - Create utility function to emit 'delivery:request' event
    - Send to specific rider room
    - Include order details, restaurant/customer addresses, fee, expiry
    - _Requirements: 8.2_

- [x] 9. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [-] 10. Restaurant Order Management Module
  - [x] 10.1 Implement order listing endpoint for restaurants
    - Create GET /orders endpoint with restaurant role filter
    - Return orders for authenticated restaurant owner's restaurant
    - Support filtering by status
    - _Requirements: 7.6_

  - [x] 10.2 Implement order status update endpoint for restaurants
    - Create PUT /orders/:id/status endpoint (restaurant role only)
    - Allow transition from 'confirmed' to 'ready_for_pickup'
    - Verify ownership before allowing update
    - Trigger rider dispatch when status becomes 'ready_for_pickup'
    - _Requirements: 7.4, 7.5_

  - [x] 10.3 Write property tests for restaurant order management
    - **Property 34: Orders auto-confirmed on successful payment**
    - **Property 35: Ready for pickup triggers rider dispatch**
    - **Validates: Requirements 7.3, 7.5**

  - [x] 10.4 Implement estimated prep time setting
    - Add estimated_prep_time_minutes field to order update
    - Store in database
    - _Requirements: 7.7_

- [x] 11. Rider Dispatch and Delivery Module
  - [x] 11.1 Implement rider location update endpoint
    - Create PUT /riders/location endpoint (rider role only)
    - Accept latitude, longitude, availability status
    - Store in rider_locations table with timestamp
    - _Requirements: 18.2, 18.3, 18.4_

  - [x] 11.2 Write property test for rider location storage
    - **Property 63: Rider location updates stored with timestamp**
    - **Validates: Requirements 18.4**

  - [x] 11.3 Implement rider availability toggle endpoint
    - Create PUT /riders/availability endpoint (rider role only)
    - Accept availability status ('available', 'on_delivery', 'offline')
    - Update rider_locations table
    - _Requirements: 8.10, 18.1_

  - [x] 11.4 Implement rider dispatch algorithm
    - Create service function triggered when order becomes 'ready_for_pickup'
    - Query available riders within configurable radius (default 5km)
    - Calculate distance using Haversine formula
    - Sort riders by distance ascending
    - Send delivery request to nearest rider via WebSocket
    - Start 60-second timeout
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 11.5 Write property tests for rider dispatch
    - **Property 36: Dispatch identifies riders within radius**
    - **Property 37: Dispatch sends request to nearest rider first**
    - **Property 64: Recent rider location used for dispatch**
    - **Validates: Requirements 8.1, 8.2, 18.6**

  - [x] 11.6 Implement delivery request acceptance endpoint
    - Create POST /deliveries/:id/accept endpoint (rider role only)
    - Update order status to 'rider_assigned'
    - Update rider availability to 'on_delivery'
    - Cancel pending requests to other riders
    - _Requirements: 8.4_

  - [x] 11.7 Write property test for delivery acceptance
    - **Property 38: Rider acceptance updates order and rider status**
    - **Validates: Requirements 8.4**

  - [x] 11.7 Implement delivery request decline endpoint
    - Create POST /deliveries/:id/decline endpoint (rider role only)
    - Trigger dispatch to next nearest rider
    - _Requirements: 8.5_

  - [x] 11.8 Write property test for delivery decline
    - **Property 39: Rider decline triggers next rider contact**
    - **Validates: Requirements 8.5**

  - [x] 11.9 Implement dispatch timeout and admin alert
    - Track dispatch start time
    - If no acceptance within 10 minutes, send admin alert
    - Keep order in 'ready_for_pickup' status
    - _Requirements: 8.6_

  - [x] 11.10 Write property test for dispatch timeout
    - **Property 40: Unaccepted delivery after timeout alerts admin**
    - **Validates: Requirements 8.6**

  - [x] 11.11 Implement pickup confirmation endpoint
    - Create PUT /deliveries/:id/pickup endpoint (rider role only)
    - Update order status to 'picked_up'
    - _Requirements: 8.7_

  - [x] 11.12 Write property test for pickup confirmation
    - **Property 41: Pickup confirmation updates order status**
    - **Validates: Requirements 8.7**

  - [x] 11.13 Implement delivery confirmation endpoint
    - Create PUT /deliveries/:id/deliver endpoint (rider role only)
    - Update order status to 'delivered'
    - Update rider availability to 'available'
    - _Requirements: 8.8_

  - [x] 11.14 Write property test for delivery confirmation
    - **Property 42: Delivery confirmation updates order and rider status**
    - **Validates: Requirements 8.8**

- [x] 12. Order Cancellation Module
  - [x] 12.1 Implement order cancellation endpoint
    - Create PUT /orders/:id/cancel endpoint (customer role only)
    - Allow cancellation only for 'confirmed' or 'ready_for_pickup' status
    - Reject cancellation for 'rider_assigned' or 'picked_up' with 409 error
    - Update order status to 'cancelled'
    - Record cancellation reason and timestamp
    - Notify restaurant if status was 'ready_for_pickup'
    - Initiate Chapa refund
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_

  - [x] 12.2 Write property tests for order cancellation
    - **Property 59: Confirmed order cancellation triggers refund**
    - **Property 60: Ready for pickup cancellation triggers refund and notification**
    - **Property 61: Cancellation rejected for assigned or picked up orders**
    - **Property 62: Cancellation records reason and timestamp**
    - **Validates: Requirements 17.2, 17.3, 17.4, 17.5**

  - [x] 12.3 Implement Chapa refund integration
    - Create service function to initiate refund via Chapa API
    - Accept order_id and refund_amount
    - Call Chapa refund endpoint
    - Store refund status in database
    - _Requirements: 13.5_

  - [x] 12.4 Write property test for refund initiation
    - **Property 51: Refund resolution initiates Chapa refund**
    - **Validates: Requirements 13.5**

- [x] 13. Ratings and Reviews Module
  - [x] 13.1 Implement rating submission endpoint
    - Create POST /orders/:id/rate endpoint (customer role only)
    - Accept restaurant_rating (1-5), rider_rating (1-5), optional review text
    - Verify order status is 'delivered'
    - Verify order belongs to authenticated customer
    - Check for duplicate rating and return 409 if exists
    - Store ratings in ratings table
    - Recalculate and update average ratings for restaurant and rider
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x] 13.2 Write property tests for ratings
    - **Property 45: Valid rating submission stored**
    - **Property 46: Duplicate rating rejected**
    - **Property 47: Average rating recalculated on new submission**
    - **Validates: Requirements 10.2, 10.3, 10.4**

  - [x] 13.3 Implement rating retrieval endpoints
    - Create GET /restaurants/:id/ratings endpoint
    - Create GET /riders/:id/ratings endpoint
    - Return paginated list of ratings with reviews
    - _Requirements: 10.5, 10.6_

- [x] 14. Dispute Management Module
  - [x] 14.1 Implement dispute submission endpoint
    - Create POST /disputes endpoint (customer role only)
    - Accept order_id, reason, optional evidence_url
    - Verify order belongs to authenticated customer
    - Create dispute record with status 'open'
    - Send admin notification
    - _Requirements: 13.1, 13.2_

  - [x] 14.2 Write property test for dispute submission
    - **Property 50: Dispute submission creates record**
    - **Validates: Requirements 13.2**

  - [x] 14.3 Implement dispute listing endpoint (admin only)
    - Create GET /disputes endpoint with admin RBAC
    - Return all disputes with order details and customer info
    - Support filtering by status
    - _Requirements: 13.3_

  - [x] 14.4 Implement dispute resolution endpoint (admin only)
    - Create PUT /disputes/:id/resolve endpoint with admin RBAC
    - Accept resolution ('refund', 'partial_refund', 'no_action')
    - Accept refund_amount for refund resolutions
    - Accept admin_notes
    - Update dispute status to 'resolved'
    - Initiate Chapa refund if applicable
    - Send WebSocket notification to customer
    - _Requirements: 13.4, 13.5, 13.6_

  - [x] 14.5 Write property test for dispute resolution
    - **Property 52: Dispute resolution triggers customer notification**
    - **Validates: Requirements 13.6**

- [x] 15. Push Notifications Module
  - [x] 15.1 Set up Firebase Admin SDK for Node.js
    - Install firebase-admin
    - Initialize with service account credentials from environment
    - Create utility function to send FCM notifications
    - _Requirements: 15.6_

  - [x] 15.2 Implement FCM token registration endpoint
    - Create POST /users/fcm-token endpoint
    - Accept token and device_type
    - Store in fcm_tokens table with user_id
    - Handle duplicate tokens gracefully
    - _Requirements: 15.4_

  - [x] 15.3 Implement push notification for order status changes
    - Send notification when order becomes 'rider_assigned', 'picked_up', 'delivered'
    - Fetch customer's FCM tokens from database
    - Call FCM utility function
    - Implement retry logic with exponential backoff
    - _Requirements: 15.1_

  - [x] 15.4 Write property test for order status push notifications
    - **Property 53: Order status change triggers customer push notification**
    - **Validates: Requirements 15.1**

  - [x] 15.5 Implement push notification for confirmed orders
    - Send notification when order becomes 'confirmed'
    - Fetch restaurant owner's FCM tokens
    - Call FCM utility function
    - _Requirements: 15.2_

  - [x] 15.6 Write property test for restaurant push notifications
    - **Property 54: Confirmed order triggers restaurant push notification**
    - **Validates: Requirements 15.2**

  - [x] 15.7 Implement push notification for delivery requests
    - Send notification when delivery request is sent to rider
    - Fetch rider's FCM tokens
    - Call FCM utility function
    - _Requirements: 15.3_

  - [x] 15.8 Write property test for rider push notifications
    - **Property 55: Delivery request triggers rider push notification**
    - **Validates: Requirements 15.3**

- [x] 16. User Profile Management Module
  - [x] 16.1 Implement profile retrieval endpoint
    - Create GET /users/profile endpoint
    - Return authenticated user's profile data
    - _Requirements: 19.1_

  - [x] 16.2 Implement profile update endpoint
    - Create PUT /users/profile endpoint
    - Accept display_name, phone, profile_photo_url
    - Validate phone number format
    - Upload profile photo to Cloudinary if provided
    - Store Cloudinary URL in database
    - _Requirements: 19.1, 19.2, 19.4_

  - [x] 16.3 Write property tests for profile management
    - **Property 65: Profile photo URL stored**
    - **Property 66: Invalid phone number rejected**
    - **Validates: Requirements 19.2, 19.4**

  - [x] 16.4 Implement password change endpoint
    - Create PUT /users/password endpoint
    - Accept current_password and new_password
    - Verify current password with bcrypt
    - Hash new password and update database
    - _Requirements: 19.5_

  - [x] 16.5 Write property test for password change
    - **Property 67: Password change requires current password**
    - **Validates: Requirements 19.5**

  - [x] 16.6 Implement address management endpoints
    - Create POST /users/addresses endpoint to add address
    - Create GET /users/addresses endpoint to list addresses
    - Create DELETE /users/addresses/:id endpoint to delete address
    - Support is_default flag for default address
    - _Requirements: 19.3_

- [-] 17. Admin Dashboard Backend Module
  - [x] 17.1 Implement admin restaurant management endpoints
    - Create GET /admin/restaurants endpoint (admin only)
    - Return all restaurants with status, owner info, menu count
    - Support filtering by status
    - _Requirements: 11.1, 11.5_

  - [x] 17.2 Implement admin user management endpoints
    - Create GET /admin/users endpoint (admin only)
    - Return searchable, paginated list of all users
    - Include registration date, order count, status
    - Create PUT /admin/users/:id/suspend endpoint
    - Create PUT /admin/users/:id/reactivate endpoint
    - Invalidate refresh tokens on suspension
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

  - [x] 17.3 Write property test for user suspension
    - **Property 49: Suspended user tokens invalidated and login rejected**
    - **Validates: Requirements 12.3**

  - [x] 17.4 Implement admin analytics endpoints
    - Create GET /admin/analytics endpoint (admin only)
    - Accept date_range parameter
    - Aggregate total orders, revenue, active users
    - Aggregate orders by status breakdown
    - Return top 10 restaurants by order volume
    - Return top 10 riders by completed deliveries
    - Optimize queries to return within 2 seconds
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

- [-] 18. API Consistency and Error Handling Module
  - [x] 18.1 Implement consistent JSON response envelope
    - Create response utility function
    - Return { success: boolean, data: any, error: string | null }
    - Apply to all endpoints
    - _Requirements: 20.1_

  - [x] 18.2 Write property test for response envelope
    - **Property 68: API responses follow consistent envelope**
    - **Validates: Requirements 20.1**

  - [x] 18.3 Implement request validation middleware
    - Use express-validator or Zod for schema validation
    - Return 422 errors with field-level details for invalid input
    - Apply to all endpoints with request bodies
    - _Requirements: 20.2_

  - [x] 18.4 Write property test for validation errors
    - **Property 69: Invalid request bodies return 422**
    - **Validates: Requirements 20.2**

  - [x] 18.5 Implement error logging middleware
    - Generate request ID (UUID) per request
    - Log all errors with timestamp, request ID, user ID, method, path, stack trace
    - Sanitize sensitive data from logs
    - Write logs to stdout in JSON format
    - _Requirements: 20.5_

  - [x] 18.6 Implement 404 and 403 error handlers
    - Return 404 for non-existent resource IDs
    - Return 403 for unauthorized resource access
    - _Requirements: 20.6_

  - [x] 18.7 Write property tests for error responses
    - **Property 72: Non-existent resources return 404**
    - **Property 73: Unauthorized resource access returns 403**
    - **Validates: Requirements 20.6**

- [x] 19. Checkpoint - Ensure all backend tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 20. Customer Flutter App - Project Setup and Authentication
  - [x] 20.1 Initialize Flutter project for Customer app
    - Create new Flutter project with appropriate package name
    - Add dependencies: dio, riverpod, flutter_secure_storage, socket_io_client, flutter_mapbox_gl, firebase_messaging
    - Set up project structure: lib/models, lib/providers, lib/screens, lib/services, lib/widgets
    - Configure Android and iOS permissions for location, notifications
    - _Requirements: 1.8_

  - [x] 20.2 Implement authentication service and secure storage
    - Create AuthService with Dio HTTP client
    - Implement register, login, refresh, logout methods
    - Store JWT and refresh token using flutter_secure_storage
    - Implement automatic token refresh on 401 errors
    - _Requirements: 1.8, 1.9_

  - [x] 20.3 Create authentication state provider with Riverpod
    - Create AuthStateNotifier to manage authentication state
    - Expose current user, isAuthenticated, loading states
    - Implement login, register, logout actions
    - _Requirements: 1.8_

  - [x] 20.4 Build login and registration screens
    - Create LoginScreen with email and password fields
    - Create RegisterScreen with email, password, role selection
    - Add form validation
    - Show loading indicators during API calls
    - Navigate to home screen on success
    - _Requirements: 1.1, 1.4_

- [x] 21. Customer Flutter App - Restaurant Browse and Search
  - [x] 21.1 Implement restaurant service and data models
    - Create Restaurant model with fromJson/toJson
    - Create RestaurantService with Dio
    - Implement getRestaurants, searchRestaurants, getRestaurantDetails methods
    - _Requirements: 4.1, 4.3_

  - [x] 21.2 Create restaurant listing provider
    - Create RestaurantListNotifier with Riverpod
    - Implement pagination support
    - Implement category filtering
    - Implement search functionality
    - _Requirements: 4.2, 4.3, 4.4_

  - [x] 21.3 Build restaurant listing screen
    - Display grid/list of restaurants with cover image, name, rating
    - Add search bar at top
    - Add category filter chips
    - Implement infinite scroll pagination
    - Navigate to restaurant detail on tap
    - _Requirements: 4.5_

  - [x] 21.4 Build restaurant detail screen
    - Display restaurant info, logo, cover image, rating
    - Display menu items grouped by category
    - Show item name, description, price, image
    - Add "Add to Cart" button for each item
    - _Requirements: 4.6_

- [x] 22. Customer Flutter App - Cart and Checkout
  - [x] 22.1 Implement cart state provider
    - Create CartNotifier with Riverpod
    - Implement addItem, removeItem, updateQuantity, clearCart methods
    - Validate single restaurant constraint
    - Calculate subtotal, delivery fee, total in real-time
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 22.2 Build cart screen
    - Display cart items with quantity controls
    - Show subtotal, delivery fee, total
    - Add "Proceed to Checkout" button
    - Validate item availability before checkout
    - Show error if items unavailable
    - _Requirements: 5.5, 5.6_

  - [x] 22.3 Implement order service
    - Create OrderService with Dio
    - Implement createOrder method
    - Return payment URL from backend
    - _Requirements: 6.1, 6.2_

  - [x] 22.4 Build checkout and payment flow
    - Create CheckoutScreen with delivery address selection
    - Show order summary
    - Call createOrder API
    - Open payment URL in WebView or external browser
    - Handle payment callback/redirect
    - Show payment confirmation screen
    - _Requirements: 6.7_

- [x] 23. Customer Flutter App - Real-Time Order Tracking
  - [x] 23.1 Implement WebSocket service
    - Create SocketService with socket_io_client
    - Connect with JWT authentication
    - Join user room on connection
    - Listen for 'order:status_changed' and 'rider:location_update' events
    - Implement reconnection logic with exponential backoff
    - _Requirements: 9.1, 9.6_

  - [x] 23.2 Create order tracking provider
    - Create OrderTrackingNotifier with Riverpod
    - Subscribe to WebSocket events
    - Update order status in real-time
    - Update rider location in real-time
    - _Requirements: 9.2_

  - [x] 23.3 Build order tracking screen
    - Display current order status with descriptive messages
    - Show rider name and ETA when status is 'rider_assigned'
    - Show live map with rider location when status is 'picked_up'
    - Use flutter_mapbox_gl for map display
    - Update map marker as rider moves
    - Add "Cancel Order" button for eligible statuses
    - _Requirements: 9.3, 9.4, 9.7_

  - [x] 23.4 Implement order cancellation
    - Create cancelOrder method in OrderService
    - Show confirmation dialog before cancellation
    - Call backend API
    - Navigate back on success
    - _Requirements: 17.1_

- [x] 24. Customer Flutter App - Ratings, Profile, and Notifications
  - [x] 24.1 Implement rating submission
    - Create RatingService with Dio
    - Build rating dialog with star rating and review text field
    - Show dialog when order status becomes 'delivered'
    - Submit rating to backend
    - _Requirements: 10.1_

  - [x] 24.2 Build profile management screen
    - Display user profile with photo, name, phone
    - Add edit button to update profile
    - Implement profile photo upload to Cloudinary
    - Add password change form
    - _Requirements: 19.1, 19.5_

  - [x] 24.3 Build address management screen
    - List saved addresses
    - Add "Add Address" button
    - Implement address form with Google Maps autocomplete
    - Mark default address
    - _Requirements: 19.3_

  - [x] 24.4 Implement push notifications
    - Set up Firebase Cloud Messaging
    - Request notification permissions on first launch
    - Register FCM token with backend
    - Handle foreground notifications with in-app banner
    - Handle background notifications
    - _Requirements: 15.4, 15.5_

  - [x] 24.5 Build order history screen
    - List past orders with status and date
    - Navigate to order detail on tap
    - Show "Rate Order" button for delivered orders without rating
    - _Requirements: 9.2_

- [x] 25. Restaurant Flutter App - Setup and Order Management
  - [x] 25.1 Initialize Flutter project for Restaurant app
    - Create new Flutter project with appropriate package name
    - Add same dependencies as Customer app
    - Set up project structure
    - Reuse authentication service and models from Customer app
    - _Requirements: 1.8_

  - [x] 25.2 Build restaurant registration screen
    - Create form with name, description, address, coordinates
    - Add logo and cover image upload to Cloudinary
    - Submit to backend
    - Show pending approval message
    - _Requirements: 2.1, 2.5_

  - [x] 25.3 Implement order management service
    - Create OrderService with Dio
    - Implement getOrders, updateOrderStatus methods
    - _Requirements: 7.6_

  - [x] 25.4 Build incoming orders screen
    - Connect to WebSocket for real-time order notifications
    - Display list of orders grouped by status
    - Show order details: items, customer address, total
    - Add "Mark Ready" button for confirmed orders
    - Play sound/vibration on new order
    - _Requirements: 7.2, 7.4_

  - [x] 25.5 Implement order status update
    - Call updateOrderStatus API when "Mark Ready" is tapped
    - Update local state
    - Show success message
    - _Requirements: 7.5_

- [x] 26. Restaurant Flutter App - Menu Management
  - [x] 26.1 Implement menu service
    - Create MenuService with Dio
    - Implement getMenuItems, createMenuItem, updateMenuItem, deleteMenuItem, toggleAvailability methods
    - _Requirements: 3.1_

  - [x] 26.2 Build menu management screen
    - Display list of menu items grouped by category
    - Show item name, price, image, availability status
    - Add "Add Item" floating action button
    - Add edit and delete buttons for each item
    - Add availability toggle switch
    - _Requirements: 3.4_

  - [x] 26.3 Build menu item form screen
    - Create form with name, description, price, category, image fields
    - Implement image upload to Cloudinary
    - Validate all required fields
    - Submit to backend
    - _Requirements: 3.2, 3.3_

  - [x] 26.4 Implement push notifications for new orders
    - Handle FCM notifications for confirmed orders
    - Show notification with order details
    - Navigate to order detail on tap
    - _Requirements: 15.2_

- [x] 27. Rider Flutter App - Setup and Delivery Management
  - [x] 27.1 Initialize Flutter project for Rider app
    - Create new Flutter project with appropriate package name
    - Add same dependencies as Customer app
    - Set up project structure
    - Reuse authentication service and models
    - _Requirements: 1.8_

  - [x] 27.2 Implement rider location service
    - Create LocationService using geolocator package
    - Get current location with high accuracy
    - Send location updates to backend every 10 seconds when on delivery
    - Send location updates every 30 seconds when available
    - Handle location permission requests
    - _Requirements: 18.2, 18.3_

  - [x] 27.3 Build availability toggle screen
    - Display current availability status
    - Add toggle button for available/offline
    - Start/stop location updates based on availability
    - _Requirements: 8.10, 18.1_

  - [x] 27.4 Implement delivery request handling
    - Connect to WebSocket for delivery requests
    - Listen for 'delivery:request' events
    - Show full-screen notification with order details
    - Add "Accept" and "Decline" buttons
    - Implement 60-second countdown timer
    - Auto-decline on timeout
    - _Requirements: 8.2, 8.3_

  - [x] 27.5 Build active delivery screen
    - Display order details: restaurant address, customer address, fee
    - Show "Navigate to Restaurant" button
    - Show "Confirm Pickup" button when at restaurant
    - Show "Navigate to Customer" button after pickup
    - Show "Confirm Delivery" button when at customer
    - Use flutter_mapbox_gl for navigation
    - _Requirements: 8.7, 8.8, 8.9_

  - [x] 27.6 Implement delivery status updates
    - Call accept/decline delivery APIs
    - Call pickup confirmation API
    - Call delivery confirmation API
    - Update local state and UI
    - _Requirements: 8.4, 8.5_

  - [x] 27.7 Implement push notifications for delivery requests
    - Handle FCM notifications for new delivery requests
    - Show notification with sound/vibration
    - Navigate to delivery request screen on tap
    - _Requirements: 15.3_

- [x] 28. Checkpoint - Ensure all Flutter apps build and run
  - Ensure all tests pass, ask the user if questions arise.

- [x] 29. Admin Dashboard - Next.js Setup and Authentication
  - [x] 29.1 Initialize Next.js project with App Router
    - Create new Next.js 14+ project with TypeScript
    - Add dependencies: axios or fetch, socket.io-client, tailwindcss or material-ui
    - Set up project structure: app/, components/, lib/, types/
    - Configure environment variables for API URL
    - _Requirements: 20.1_

  - [x] 29.2 Implement authentication service
    - Create auth service with fetch/axios
    - Implement login, logout, token refresh
    - Store JWT in httpOnly cookies or localStorage
    - Create auth context/provider
    - _Requirements: 1.4, 1.9_

  - [x] 29.3 Build login page
    - Create login form with email and password
    - Add form validation
    - Navigate to dashboard on success
    - Show error messages
    - _Requirements: 1.4_

  - [x] 29.4 Create protected route wrapper
    - Check authentication status
    - Redirect to login if not authenticated
    - Verify admin role
    - _Requirements: 1.10_

- [x] 30. Admin Dashboard - Restaurant Management
  - [x] 30.1 Build restaurant management page
    - Create table/list of all restaurants
    - Display name, owner, status, menu count
    - Add status filter dropdown
    - Add search functionality
    - Show "View Details" button for each restaurant
    - _Requirements: 11.1, 11.5_

  - [x] 30.2 Build restaurant detail modal/page
    - Display full restaurant details
    - Show logo, cover image, address, coordinates
    - Show owner information
    - Add "Approve" and "Reject" buttons for pending restaurants
    - Add "Suspend" button for approved restaurants
    - _Requirements: 11.2, 11.3_

  - [x] 30.3 Implement restaurant approval/rejection/suspension
    - Call backend APIs for approve, reject, suspend
    - Show confirmation dialogs
    - Update table on success
    - _Requirements: 11.2, 11.3_

- [x] 31. Admin Dashboard - User Management
  - [x] 31.1 Build user management page
    - Create table of all users (customers, restaurants, riders)
    - Display email, role, registration date, order count, status
    - Add search by email
    - Add role filter
    - Add pagination
    - _Requirements: 12.1, 12.4_

  - [x] 31.2 Implement user suspension and reactivation
    - Add "Suspend" button for active users
    - Add "Reactivate" button for suspended users
    - Call backend APIs
    - Show confirmation dialogs
    - Update table on success
    - _Requirements: 12.2_

- [x] 32. Admin Dashboard - Dispute Management
  - [x] 32.1 Build dispute management page
    - Create table of all disputes
    - Display order ID, customer, reason, status, date
    - Add status filter (open/resolved)
    - Show "View Details" button for each dispute
    - _Requirements: 13.3_

  - [x] 32.2 Build dispute detail modal/page
    - Display full dispute details
    - Show order information
    - Show customer information
    - Show evidence image if provided
    - Add resolution form with outcome dropdown (refund, partial_refund, no_action)
    - Add refund amount field for refund outcomes
    - Add admin notes text area
    - _Requirements: 13.4_

  - [x] 32.3 Implement dispute resolution
    - Call backend API to resolve dispute
    - Show confirmation dialog
    - Update table on success
    - _Requirements: 13.4_

- [x] 33. Admin Dashboard - Analytics
  - [x] 33.1 Build analytics dashboard page
    - Add date range picker
    - Display total orders card
    - Display total revenue card
    - Display active users card
    - Display orders by status breakdown (pie chart or bar chart)
    - Display top 10 restaurants by order volume (table)
    - Display top 10 riders by completed deliveries (table)
    - _Requirements: 14.1, 14.2, 14.3, 14.4_

  - [x] 33.2 Implement analytics data fetching
    - Call backend analytics API with date range
    - Handle loading states
    - Display charts using charting library (recharts, chart.js)
    - _Requirements: 14.5_

- [x] 34. Admin Dashboard - Real-Time Updates
  - [x] 34.1 Implement WebSocket connection
    - Create socket service with socket.io-client
    - Connect with JWT authentication
    - Listen for admin-relevant events (new disputes, unassigned orders)
    - _Requirements: 8.6_

  - [x] 34.2 Display real-time notifications
    - Show notification badge for new disputes
    - Show alert for unassigned orders > 10 minutes
    - Update tables in real-time when data changes
    - _Requirements: 8.6_

- [x] 35. Checkpoint - Ensure admin dashboard is functional
  - Ensure all tests pass, ask the user if questions arise.

- [x] 36. Deployment and Infrastructure
  - [x] 36.1 Set up Render project for backend
    - Create Render account and new Web Service
    - Connect GitHub repository
    - Configure environment variables on Render
    - Set build command: `npm install && npm run build`
    - Set start command: `npm start`
    - Set up automatic deployments on push to main
    - _Requirements: 20.1_

  - [x] 36.2 Set up Supabase database and run migrations
    - Create Supabase project and obtain DATABASE_URL
    - Run migration SQL files via Supabase SQL editor or psql
    - Verify all tables and indexes created
    - Insert initial platform_config values
    - Update Render environment variable DATABASE_URL with Supabase connection string
    - _Requirements: 20.3_

  - [x] 36.3 Configure external service integrations
    - Set up Chapa account and obtain API keys
    - Set up Cloudinary account and obtain credentials
    - Set up Firebase project and obtain service account
    - Set up Mapbox account and obtain access token
    - Add all credentials to Render environment variables
    - _Requirements: 6.2, 2.5, 15.6_

  - [x] 36.4 Deploy Next.js admin dashboard to Vercel
    - Create Vercel project and connect GitHub repository
    - Configure environment variables (NEXT_PUBLIC_API_URL)
    - Set up automatic deployments on push
    - _Requirements: 20.1_

  - [x] 36.5 Build and publish Flutter apps
    - Build Android APK/AAB for Customer app
    - Build Android APK/AAB for Restaurant app
    - Build Android APK/AAB for Rider app
    - Build iOS IPA for all three apps (if applicable)
    - Submit to Google Play Store and Apple App Store
    - _Requirements: 1.1_

- [x] 37. Integration Testing and End-to-End Validation
  - [x] 37.1 Write integration tests for complete order flow
    - Test customer order creation through delivery
    - Test payment webhook handling
    - Test rider dispatch and acceptance
    - Test real-time notifications
    - _Requirements: 6.1, 6.3, 8.4, 9.1_

  - [x] 37.2 Write integration tests for restaurant workflow
    - Test restaurant registration and approval
    - Test menu item creation and management
    - Test order reception and status updates
    - _Requirements: 2.1, 2.3, 3.1, 7.5_

  - [x] 37.3 Write integration tests for rider workflow
    - Test rider location updates
    - Test delivery request acceptance
    - Test pickup and delivery confirmation
    - _Requirements: 8.4, 8.7, 8.8, 18.4_

  - [x] 37.4 Write integration tests for admin workflows
    - Test restaurant approval/suspension
    - Test user suspension
    - Test dispute resolution
    - Test analytics queries
    - _Requirements: 11.2, 12.2, 13.4, 14.5_

  - [x] 37.5 Perform end-to-end testing with all clients
    - Test complete user journey from registration to delivery
    - Test WebSocket connectivity across all clients
    - Test push notifications on real devices
    - Test payment flow with Chapa sandbox
    - Verify all 73 correctness properties hold in production-like environment

- [x] 38. Final Checkpoint and Production Readiness
  - [x] 38.1 Review and validate all correctness properties
    - Verify all 73 property-based tests pass
    - Review test coverage reports
    - Ensure minimum 80% backend coverage, 70% Flutter coverage
    - _Requirements: All_

  - [x] 38.2 Security audit and hardening
    - Review all authentication and authorization logic
    - Verify input validation on all endpoints
    - Test rate limiting
    - Verify HTTPS enforcement
    - Review error logging for sensitive data leaks
    - _Requirements: 20.1, 20.2_

  - [x] 38.3 Performance testing and optimization
    - Load test backend API with realistic traffic
    - Verify API response times < 2 seconds
    - Test WebSocket connection limits
    - Optimize database queries with EXPLAIN ANALYZE
    - Add database indexes if needed
    - _Requirements: 14.5_

  - [x] 38.4 Set up monitoring and alerting
    - Configure Railway monitoring for error rates
    - Set up alerts for API response time degradation
    - Set up alerts for database connection failures
    - Set up alerts for unassigned orders > 10 minutes
    - Configure log aggregation
    - _Requirements: 8.6_

  - [x] 38.5 Create deployment documentation
    - Document environment variables
    - Document database migration process
    - Document external service setup
    - Document monitoring and alerting setup
    - Create runbook for common issues

  - [x] 38.6 Final production deployment
    - Deploy backend to Railway production environment
    - Deploy admin dashboard to production
    - Publish Flutter apps to app stores
    - Verify all services are running
    - Perform smoke tests on production

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP delivery
- Each task references specific requirements for traceability
- Property-based tests validate the 73 correctness properties from the design document
- Checkpoints ensure incremental validation at key milestones
- The implementation follows a backend-first approach, then mobile apps, then admin dashboard
- All external integrations (Chapa, Cloudinary, Firebase, Google Maps) are configured during deployment phase
- Testing is integrated throughout the implementation, not left to the end

