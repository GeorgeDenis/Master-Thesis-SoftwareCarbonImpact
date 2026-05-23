-- sql/02_index_apply.sql
-- Apply the B-tree index for the S3 optimization. Run before the OPTIMIZE_S3_INDEX=1 phase.
CREATE INDEX IF NOT EXISTS idx_medical_records_disease ON medical_records(disease);
ANALYZE medical_records;
