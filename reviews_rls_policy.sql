-- Enable RLS on reviews table
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- Policy: Riders can view reviews for their own rides
CREATE POLICY "Riders can view reviews for their completed rides"
ON reviews FOR SELECT
USING (
  ride_id IN (
    SELECT id FROM rides WHERE rider_id = auth.uid()
  )
);

-- Policy: Riders can insert reviews for their own completed rides
CREATE POLICY "Riders can insert reviews for their completed rides"
ON reviews FOR INSERT
WITH CHECK (
  rider_id = auth.uid()
  AND ride_id IN (
    SELECT id FROM rides WHERE rider_id = auth.uid() AND status = 'completed'
  )
);

-- Policy: Drivers can view reviews about themselves
CREATE POLICY "Drivers can view reviews about themselves"
ON reviews FOR SELECT
USING (driver_id = auth.uid());

-- Policy: Service role can manage all reviews
CREATE POLICY "Service role can manage all reviews"
ON reviews
FOR ALL
USING (true)
WITH CHECK (true);
