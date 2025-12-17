-- Add cancelled_at column to ride_requests table

ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE;

-- Add cancelled_at column to rides table as well for consistency
ALTER TABLE rides ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP WITH TIME ZONE;
