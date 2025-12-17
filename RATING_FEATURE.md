# Rating Feature Implementation

## Overview
The rating feature allows riders to rate their completed trips and drivers in the CampusRide app. Riders can submit a rating (1-5 stars) and optional comment about their driving experience.

## Features

### 1. Rating Dialog (`lib/rating_dialog.dart`)
- Beautiful dialog with driver avatar and name
- 5-star interactive rating selector
- Text field for optional feedback comment
- Submit and Skip buttons
- Loading state during submission

### 2. Trip Detail Page Integration
- "Rate Driver" button appears for completed trips
- Button navigates to the rating dialog
- Refreshes trip details after successful rating

### 3. Trip History Page Integration
- Star icon button on completed trips for quick rating
- Click to open rating dialog directly from history list
- Automatic refresh after submitting rating

## Database Setup

### Reviews Table
The `reviews` table stores all driver ratings:
```sql
CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid REFERENCES rides(id),
  rider_id uuid REFERENCES auth.users(id),
  driver_id uuid REFERENCES drivers(id),
  rating integer CHECK (rating >= 1 AND rating <= 5),
  comment text,
  created_at timestamp with time zone DEFAULT now()
);
```

### RLS Policies Required
Before the rating feature will work, you must apply the RLS policies from `reviews_rls_policy.sql`:

**Steps:**
1. Go to Supabase Dashboard → SQL Editor
2. Copy and paste contents of `reviews_rls_policy.sql`
3. Run the query

**Policies:**
- Riders can insert reviews for their completed rides
- Riders can view reviews for their own rides
- Drivers can view reviews about themselves
- Service role can manage all reviews (for admin operations)

## User Flow

### Rating from Trip Details
1. User completes a ride
2. Opens trip details via Trip History
3. Trip status shows "Completed"
4. "Rate Driver" button appears
5. Click button → Rating dialog opens
6. Select rating (1-5 stars)
7. Optionally add comment
8. Click "Submit" → Rating saved to database

### Rating from Trip History
1. User views Trip History
2. Completed trips show star icon button on the right
3. Click star icon → Rating dialog opens
4. Complete rating submission
5. Trip history refreshes

## Rating Scale

- ⭐ (1 star): Poor
- ⭐⭐ (2 stars): Fair
- ⭐⭐⭐ (3 stars): Good
- ⭐⭐⭐⭐ (4 stars): Very Good
- ⭐⭐⭐⭐⭐ (5 stars): Excellent

## Technical Details

### Database Relationships
```
Rider → Reviews ← Driver
         ↓
       Rides
```

### Data Validation
- Rating must be between 1-5
- Can only rate completed trips
- One rating per ride (enforced by app logic, can add unique constraint in database)
- Comment is optional and trimmed of whitespace

### Error Handling
- Catches RLS policy violations
- Shows user-friendly error messages
- Handles network errors gracefully
- Provides retry options

## Future Enhancements

1. **Driver Rating Display**
   - Show average rating on driver profile
   - Display recent reviews from riders
   - Rating history graph

2. **Review Management**
   - Edit rating after submission
   - Delete rating (with confirmation)
   - View all reviews by a driver

3. **Advanced Features**
   - Photo/media in reviews
   - Helpful/unhelpful voting
   - Report inappropriate review
   - In-app review moderation

4. **Analytics**
   - Driver rating trends
   - Service quality metrics
   - Rider satisfaction analysis

## Files Modified/Created

### New Files
- `lib/rating_dialog.dart` - Rating dialog widget
- `reviews_rls_policy.sql` - Database RLS policies

### Modified Files
- `lib/trip_detail.dart` - Added import and rating button for completed trips
- `lib/trip_history.dart` - Added driver cache, rating button in trip cards

## Notes

- RLS policies MUST be applied before the feature will work
- Driver ratings are stored separately from reviews (can be added to driver profile later)
- Reviews are immutable via the app (no edit functionality yet)
- Ratings are tied to specific rides for accountability
