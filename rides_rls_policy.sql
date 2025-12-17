-- Enable RLS on ride_requests table
ALTER TABLE ride_requests ENABLE ROW LEVEL SECURITY;

-- Policy: Riders can view their own ride requests
CREATE POLICY "Riders can view their own ride requests"
ON ride_requests FOR SELECT
USING (rider_id = auth.uid());

-- Policy: Riders can insert their own ride requests
CREATE POLICY "Riders can insert their own ride requests"
ON ride_requests FOR INSERT
WITH CHECK (rider_id = auth.uid());

-- Policy: Riders can update their own ride requests
CREATE POLICY "Riders can update their own ride requests"
ON ride_requests FOR UPDATE
USING (rider_id = auth.uid())
WITH CHECK (rider_id = auth.uid());

-- Policy: Drivers can view open ride requests
CREATE POLICY "Drivers can view open ride requests"
ON ride_requests FOR SELECT
USING (status = 'open');

-- Policy: Service role can manage all ride requests
CREATE POLICY "Service role can manage all ride requests"
ON ride_requests
FOR ALL
USING (true)
WITH CHECK (true);

-- Enable RLS on rides table
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;

-- Policy: Riders can view their own rides
CREATE POLICY "Riders can view their own rides"
ON rides FOR SELECT
USING (rider_id = auth.uid());

-- Policy: Riders can insert their own rides
CREATE POLICY "Riders can insert their own rides"
ON rides FOR INSERT
WITH CHECK (rider_id = auth.uid());

-- Policy: Riders can update their own rides
CREATE POLICY "Riders can update their own rides"
ON rides FOR UPDATE
USING (rider_id = auth.uid())
WITH CHECK (rider_id = auth.uid());

-- Policy: Drivers can view rides they're assigned to
CREATE POLICY "Drivers can view assigned rides"
ON rides FOR SELECT
USING (driver_id = auth.uid());

-- Policy: Drivers can update rides they're assigned to
CREATE POLICY "Drivers can update assigned rides"
ON rides FOR UPDATE
USING (driver_id = auth.uid())
WITH CHECK (driver_id = auth.uid());

-- Policy: Service role can manage all rides
CREATE POLICY "Service role can manage all rides"
ON rides
FOR ALL
USING (true)
WITH CHECK (true);
