-- Add rating column to drivers table if it doesn't exist
ALTER TABLE drivers
ADD COLUMN IF NOT EXISTS rating DECIMAL(3,2) DEFAULT 5.0;

-- Add comment for clarity
COMMENT ON COLUMN drivers.rating IS 'Average rating calculated from all reviews (0-5)';
