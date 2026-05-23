-- sql/02_index_drop.sql
-- Drop the B-tree index for the S3 baseline. Run before the OPTIMIZE_S3_INDEX=0 phase.
DROP INDEX IF EXISTS idx_medical_records_disease;
ANALYZE medical_records;
