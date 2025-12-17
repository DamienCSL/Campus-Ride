-- ========================================
-- CHECK EXISTING STORAGE POLICIES
-- ========================================
-- Run this query in Supabase SQL Editor to see current policies
-- ========================================

-- Query 1: Check all RLS policies on storage.objects table
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'storage' 
  AND tablename = 'objects'
ORDER BY cmd, policyname;

-- ========================================

-- Query 2: Check if the bucket exists and its configuration
SELECT 
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
FROM storage.buckets
WHERE name = 'driver_licenses';

-- ========================================

-- Query 3: More detailed policy view (alternative format)
SELECT 
    pol.policyname AS "Policy Name",
    pol.cmd AS "Operation",
    pol.qual AS "USING Expression",
    pol.with_check AS "WITH CHECK Expression"
FROM pg_policies pol
WHERE pol.schemaname = 'storage' 
  AND pol.tablename = 'objects'
  AND (pol.qual LIKE '%driver_licenses%' OR pol.with_check LIKE '%driver_licenses%')
ORDER BY pol.cmd;

-- ========================================
-- INSTRUCTIONS:
-- ========================================
-- 1. Copy Query 1 above (the first SELECT statement)
-- 2. Go to Supabase Dashboard → SQL Editor
-- 3. Paste and run the query
-- 4. Share ALL the results with me so I can see your current policies
-- 5. Also run Query 2 to check if bucket is public
-- ========================================
