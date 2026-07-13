-- ====================================================================================
-- Project: Multi-Cloud Enterprise Data Pipeline (GCP to OCI)
-- Component: High-Performance ETL & Optimized Data Export
-- Purpose: Aggregates, filters, and exports the daily 30GB transactional delta 
--          using partitioning and clustering to minimize data scan costs.
-- Author: [Tu Nombre]
-- ====================================================================================

-- Step 1: Create a temporary or staging table using PARTITION BY and CLUSTER BY
-- This demonstrates your knowledge of cost governance and query optimization.
CREATE OR REPLACE TABLE `your_project.warehouse_staging.daily_transaction_delta`
PARTITION BY DATE(transaction_timestamp)
CLUSTER BY client_industry, transaction_status
AS
SELECT 
    t.transaction_id,
    t.client_id,
    c.company_name,
    c.industry_segment AS client_industry,
    t.amount,
    t.currency,
    t.transaction_status,
    -- Target application requires formatted strings for legacy flat-file compliance
    FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', t.transaction_timestamp) AS transaction_timestamp,
    -- Generate cryptographic signature for data lineage tracking
    SHA256(CONCAT(t.transaction_id, CAST(t.amount AS STRING))) AS record_hash
FROM 
    `your_project.warehouse_raw.transactions` AS t
INNER JOIN 
    `your_project.warehouse_raw.clients` AS c 
    ON t.client_id = c.client_id
WHERE 
    -- Strict partition pruning: limits scan exclusively to the 30GB daily window
    t.transaction_timestamp >= TIMESTAMP(CURRENT_DATE() - 1)
    AND t.transaction_timestamp < TIMESTAMP(CURRENT_DATE())
    AND t.transaction_status = 'COMPLETED';


-- Step 2: Export the processed data to Cloud Storage as compressed flat files.
-- This demonstrates handling massive volumetry and network optimization.
EXPORT DATA OPTIONS(
  uri='gs://your-enterprise-staging-bucket/daily_exports/*.csv.gz',
  format='CSV',
  overwrite=true,
  header=true,
  field_delimiter=',',
  -- Enforcing Gzip compression dramatically reduces network transit footprint to OCI
  compression='GZIP'
) AS
SELECT 
    transaction_id,
    client_id,
    company_name,
    client_industry,
    -- Format numeric scales explicitly to avoid rounding mismatches in target ERP
    CAST(amount AS STRING) AS amount,
    currency,
    transaction_status,
    transaction_timestamp,
    CAST(record_hash AS STRING) AS record_hash
FROM 
    `your_project.warehouse_staging.daily_transaction_delta`
WHERE 
    DATE(transaction_timestamp) = CURRENT_DATE() - 1;
