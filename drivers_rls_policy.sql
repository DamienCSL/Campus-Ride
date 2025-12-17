-- Enable RLS on drivers table
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;

-- Policy: Drivers can view their own record
CREATE POLICY "Drivers can view their own record"
ON drivers FOR SELECT
USING (id = auth.uid());

-- Policy: Anyone can view driver information (for passenger display)
CREATE POLICY "Anyone can view driver information"
ON drivers FOR SELECT
USING (true);

-- Policy: Drivers can update their own record
CREATE POLICY "Drivers can update their own record"
ON drivers FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Policy: Service role and system functions can update driver ratings
-- This allows the rating calculation function to update the rating field
CREATE POLICY "System can update driver ratings"
ON drivers FOR UPDATE
USING (true)
WITH CHECK (true);

-- Policy: Service role can manage all drivers (for admin operations)
CREATE POLICY "Service role can manage all drivers"
ON drivers
FOR ALL
USING (true)
WITH CHECK (true);
