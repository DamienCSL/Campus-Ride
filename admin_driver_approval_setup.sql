-- Update drivers table to support admin approval workflow

-- Add foreign key constraint if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'drivers_id_fkey' AND table_name = 'drivers'
  ) THEN
    ALTER TABLE drivers ADD CONSTRAINT drivers_id_fkey 
    FOREIGN KEY (id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Add approval columns to drivers table if they don't exist
DO $$ 
BEGIN
  -- Add is_approved column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'is_approved'
  ) THEN
    ALTER TABLE drivers ADD COLUMN is_approved BOOLEAN DEFAULT false;
  END IF;

  -- Add is_rejected column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'is_rejected'
  ) THEN
    ALTER TABLE drivers ADD COLUMN is_rejected BOOLEAN DEFAULT false;
  END IF;

  -- Add rejection_reason column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'rejection_reason'
  ) THEN
    ALTER TABLE drivers ADD COLUMN rejection_reason TEXT;
  END IF;

  -- Add approved_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'approved_at'
  ) THEN
    ALTER TABLE drivers ADD COLUMN approved_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- Add rejected_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'rejected_at'
  ) THEN
    ALTER TABLE drivers ADD COLUMN rejected_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- Add is_online column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'is_online'
  ) THEN
    ALTER TABLE drivers ADD COLUMN is_online BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_drivers_is_approved ON drivers(is_approved);
CREATE INDEX IF NOT EXISTS idx_drivers_is_rejected ON drivers(is_rejected);
CREATE INDEX IF NOT EXISTS idx_drivers_is_online ON drivers(is_online);

-- Update existing drivers to be approved by default (migration)
UPDATE drivers SET is_approved = true WHERE is_approved IS NULL OR is_approved = false;

-- Add RLS policy for admins to manage drivers
DROP POLICY IF EXISTS "Admins can manage all drivers" ON drivers;
CREATE POLICY "Admins can manage all drivers"
ON drivers
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);
