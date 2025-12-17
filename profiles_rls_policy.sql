-- Enable RLS on profiles table
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own profile
CREATE POLICY "Users can view their own profile"
ON profiles FOR SELECT
USING (id = auth.uid());

-- Policy: Users can update their own profile
CREATE POLICY "Users can update their own profile"
ON profiles FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Policy: Users can insert their own profile
CREATE POLICY "Users can insert their own profile"
ON profiles FOR INSERT
WITH CHECK (id = auth.uid());

-- Policy: Anyone can view public profile information (for riders to see driver info)
CREATE POLICY "Anyone can view public profiles"
ON profiles FOR SELECT
USING (true);

-- Policy: Service role can manage all profiles
CREATE POLICY "Service role can manage all profiles"
ON profiles
FOR ALL
USING (true)
WITH CHECK (true);
