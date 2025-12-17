-- Check all driver records and their approval status

-- 1. Count all drivers
SELECT 
  'Total Drivers' as category,
  COUNT(*) as count
FROM drivers;

-- 2. Count by approval status
SELECT 
  CASE 
    WHEN is_approved = true THEN 'Approved'
    WHEN is_rejected = true THEN 'Rejected'
    WHEN is_approved = false AND is_rejected = false THEN 'Pending'
    WHEN is_approved IS NULL OR is_rejected IS NULL THEN 'NULL Status (NEEDS FIX)'
  END as status,
  COUNT(*) as count
FROM drivers
GROUP BY is_approved, is_rejected;

-- 3. Show all driver records with full details
SELECT 
  d.id,
  p.full_name,
  p.phone,
  d.license_number,
  d.vehicle_id,
  d.is_verified,
  d.is_approved,
  d.is_rejected,
  d.created_at
FROM drivers d
LEFT JOIN profiles p ON d.id = p.id
ORDER BY d.created_at DESC;

-- 4. Check if any drivers have NULL approval fields (need migration)
SELECT 
  COUNT(*) as drivers_needing_migration
FROM drivers
WHERE is_approved IS NULL OR is_rejected IS NULL;

-- 5. Show profiles with driver role but no driver record
SELECT 
  p.id,
  p.full_name,
  p.phone,
  p.role,
  p.created_at
FROM profiles p
LEFT JOIN drivers d ON p.id = d.id
WHERE p.role = 'driver'
  AND d.id IS NULL;
