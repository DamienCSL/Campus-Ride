-- Fix existing driver records that have NULL approval status fields
-- This migration is needed for drivers registered before the approval fields were added

UPDATE drivers 
SET 
  is_approved = COALESCE(is_approved, false),
  is_rejected = COALESCE(is_rejected, false),
  is_verified = COALESCE(is_verified, false)
WHERE 
  is_approved IS NULL 
  OR is_rejected IS NULL 
  OR is_verified IS NULL;

-- Verify the update
SELECT 
  COUNT(*) as updated_drivers,
  'All drivers now have proper approval status' as message
FROM drivers
WHERE 
  is_approved IS NOT NULL 
  AND is_rejected IS NOT NULL 
  AND is_verified IS NOT NULL;
