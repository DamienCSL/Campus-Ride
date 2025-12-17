-- Enable RLS on driver_locations table
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

-- Policy: Drivers can insert their own location
CREATE POLICY "Drivers can insert their own location"
ON driver_locations FOR INSERT
WITH CHECK (driver_id = auth.uid());

-- Policy: Anyone can view driver locations (riders need to track drivers)
CREATE POLICY "Anyone can view driver locations"
ON driver_locations FOR SELECT
USING (true);

-- Policy: Service role can manage all driver locations
CREATE POLICY "Service role can manage all driver locations"
ON driver_locations
FOR ALL
USING (true)
WITH CHECK (true);
