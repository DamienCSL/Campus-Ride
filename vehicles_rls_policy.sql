-- Enable RLS on vehicles table
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;

-- Idempotent policy creation: only create if missing
DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Drivers can view their own vehicles'
	) THEN
		CREATE POLICY "Drivers can view their own vehicles"
		ON vehicles FOR SELECT
		USING (driver_id = auth.uid());
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Anyone can view vehicles'
	) THEN
		CREATE POLICY "Anyone can view vehicles"
		ON vehicles FOR SELECT
		USING (true);
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Drivers can insert their own vehicles'
	) THEN
		CREATE POLICY "Drivers can insert their own vehicles"
		ON vehicles FOR INSERT
		WITH CHECK (driver_id = auth.uid());
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Drivers can update their own vehicles'
	) THEN
		CREATE POLICY "Drivers can update their own vehicles"
		ON vehicles FOR UPDATE
		USING (driver_id = auth.uid())
		WITH CHECK (driver_id = auth.uid());
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Drivers can delete their own vehicles'
	) THEN
		CREATE POLICY "Drivers can delete their own vehicles"
		ON vehicles FOR DELETE
		USING (driver_id = auth.uid());
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'public'
			AND tablename = 'vehicles'
			AND policyname = 'Service role can manage all vehicles'
	) THEN
		CREATE POLICY "Service role can manage all vehicles"
		ON vehicles
		FOR ALL
		USING (true)
		WITH CHECK (true);
	END IF;
END $$;
