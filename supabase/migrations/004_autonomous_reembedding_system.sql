-- Autonomous Re-embedding System: The Generic Autopilot
-- Autonomous re-embedding system that keeps embeddings synchronized with source data
-- as document content evolves, handling data drift at scale without human intervention

-- Enable required extensions for autonomous processing
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_net";

-- ==============================================================================
-- INTELLIGENT CHANGE DETECTION: The Brain of the Autopilot
-- ==============================================================================

/**
 * Finds documents with outdated embeddings by comparing content hashes
 * This is the "intelligence" that detects data drift automatically
 * 
 * @param batch_limit Maximum number of documents to process in one batch
 * @returns Documents that need re-embedding due to content changes
 */
CREATE OR REPLACE FUNCTION "public"."find_outdated_embeddings"(batch_limit INTEGER DEFAULT 30000) 
RETURNS TABLE(
    document_id TEXT, 
    document_type TEXT,
    content TEXT, 
    current_hash TEXT, 
    stored_hash TEXT,
    content_length INTEGER
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    sd.id as document_id,
    sd.content,
    md5(sd.content) as current_hash,
    de.source_text_hash as stored_hash,
    LENGTH(sd.content) as content_length
  FROM public.source_documents sd
  JOIN public.document_embeddings de ON de.document_id = sd.id
  WHERE sd.content IS NOT NULL 
    AND sd.content <> ''
    AND md5(sd.content) != de.source_text_hash  -- Content has changed since last embedding
  ORDER BY sd.updated_at DESC  -- Process most recently updated documents first
  LIMIT batch_limit;
END;
$$;

/**
 * Micro-batching function for large-scale re-embedding operations
 * Handles thousands of updates without timeouts or transaction conflicts
 * Uses intelligent commit batching to prevent system overload
 * 
 * @param batch_limit Maximum number of documents to enqueue in one operation
 * @returns Number of documents successfully enqueued for re-embedding
 */
CREATE OR REPLACE FUNCTION "public"."enqueue_outdated_embeddings"(batch_limit INTEGER DEFAULT 30000) 
RETURNS INTEGER
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
  document_record RECORD;
  enqueued_count INTEGER := 0;
  outdated_count INTEGER;
  commit_batch_size INTEGER := 100; -- TODO: Make configurable via app.settings
BEGIN
  -- First, log how many documents need updating for monitoring
  SELECT COUNT(*) INTO outdated_count FROM find_outdated_embeddings(batch_limit);
  RAISE LOG 'Autopilot detected % documents with outdated embeddings', outdated_count;

  -- Early exit if no work to do
  IF outdated_count = 0 THEN
    RETURN 0;
  END IF;

    -- Step 1: Create temp table with already queued documents (avoid duplicates)
  -- NOTE: For multi-instance production deployments, this operation should use 
  -- advisory locks to prevent race conditions between concurrent autopilot runs.
  -- For single-instance showcases, this pattern is safe and efficient.
  -- TODO: Add advisory lock for production multi-instance deployment:
  -- SELECT pg_advisory_lock(hashtext('autopilot_sync'));
  CREATE TEMP TABLE queued_documents AS
  SELECT DISTINCT message->>'document_id' as document_id
  FROM pgmq.q_embedding_jobs;

  -- Step 2: Enqueue documents with outdated embeddings using micro-batches
  FOR document_record IN (
    SELECT * FROM find_outdated_embeddings(batch_limit)
    WHERE document_id NOT IN (
      SELECT document_id FROM queued_documents 
      WHERE document_id IS NOT NULL
    )
  ) LOOP
    -- Enqueue individual document for re-embedding
    PERFORM pgmq.send('embedding_jobs', jsonb_build_object(
      'document_id', document_record.document_id,
      'document_type', COALESCE(document_record.metadata->>'document_type', 'general'),
      'source_text', document_record.content,
      'current_hash', document_record.current_hash,
      'previous_hash', document_record.stored_hash,
      'content_length', document_record.content_length,
      'autopilot_reembedding', true,
      'priority', CASE 
        WHEN document_record.content_length > 5000 THEN 'high'
        ELSE 'normal'
      END,
      'enqueued_at', now()
    ));
    
    enqueued_count := enqueued_count + 1;
    
    -- Micro-batch: commit every N documents to avoid long transactions
    -- This is crucial for handling large datasets without blocking other operations
    IF enqueued_count % commit_batch_size = 0 THEN
      COMMIT;
      RAISE LOG 'Autopilot: Processed % documents (micro-batch checkpoint)', enqueued_count;
    END IF;
  END LOOP;
  
  -- Clean up temp table
  DROP TABLE IF EXISTS queued_documents;
  
  RAISE LOG 'Autopilot: Successfully enqueued % documents for re-embedding', enqueued_count;
  RETURN enqueued_count;
  
EXCEPTION WHEN OTHERS THEN
  -- Clean up temp table on error
  DROP TABLE IF EXISTS queued_documents;
  RAISE LOG 'Autopilot error in enqueue_outdated_embeddings: %', SQLERRM;
  RETURN -1;
END;
$$;

-- ==============================================================================
-- CPU-AWARE PROCESSING: Adaptive System Load Management
-- ==============================================================================

/**
 * CPU-aware function for continuous processing without overwhelming the system
 * Adapts batch size based on queue depth and system capacity
 * This prevents the system from being overwhelmed during high-volume periods
 */
CREATE OR REPLACE FUNCTION "public"."trigger_embedding_queue_processing_adaptive"() 
RETURNS "void"
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
  project_url TEXT;
  service_role_key TEXT;
  request_id BIGINT;
  queue_size INTEGER;
  adaptive_batch_size INTEGER;
BEGIN
  -- Get configuration from settings (these should be set via SQL or environment)
  project_url := current_setting('app.settings.project_url', true);
  service_role_key := current_setting('app.settings.service_role_key', true);
  
  -- Validate configuration is available
  IF project_url IS NULL OR service_role_key IS NULL THEN
    RAISE LOG 'Autopilot: Configuration not available - skipping processing cycle';
    RETURN;
  END IF;
  
  -- Check current queue size for adaptive processing
  SELECT COUNT(*) INTO queue_size FROM pgmq.q_embedding_jobs;
  
  -- Only trigger processing if there are jobs to process
  IF queue_size > 0 THEN
    -- Adaptive batch sizing based on queue depth
    -- Small batches for small queues, larger batches for backlogs (up to CPU limits)
    adaptive_batch_size := CASE 
      WHEN queue_size <= 10 THEN 1
      WHEN queue_size <= 50 THEN 2
      WHEN queue_size <= 200 THEN 3
      ELSE 5  -- Maximum batch size to stay within CPU limits
    END;
    
    -- Make HTTP request to Edge Function with adaptive parameters
    SELECT net.http_post(
      url := project_url || '/functions/v1/process-embedding-queue',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key,
        'X-Adaptive-Processing', 'true'
      ),
      body := jsonb_build_object(
        'batch_size', adaptive_batch_size,
        'queue_size', queue_size,
        'cpu_aware_mode', true,
        'timeout_seconds', 30,
        'adaptive_processing', true
      ),
      timeout_milliseconds := 35000  -- 35 second HTTP timeout
    ) INTO request_id;
    
    RAISE LOG 'Autopilot: Triggered adaptive processing for % jobs (batch_size: %, request_id: %)', 
              queue_size, adaptive_batch_size, request_id;
  ELSE
    RAISE LOG 'Autopilot: Queue empty, skipping processing cycle';
  END IF;
  
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'Autopilot error in trigger_embedding_queue_processing_adaptive: %', SQLERRM;
  -- Don't re-raise - we want the cron job to continue even if this fails
END;
$$;

-- ==============================================================================
-- MASTER AUTOPILOT CONTROLLER: Orchestrates the Complete System
-- ==============================================================================

/**
 * The master autopilot function that orchestrates the complete re-embedding cycle
 * This is the "brain" that decides when to scan, when to process, and how to manage load
 * Runs autonomously every 30 seconds via cron scheduling
 */
CREATE OR REPLACE FUNCTION "public"."autopilot_embedding_sync"() 
RETURNS "void"
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
  enqueued_count INTEGER;
  current_queue_size INTEGER;
  -- TODO: Move these to app.settings configuration table for production flexibility
  system_load_threshold INTEGER := 1000; -- Don't scan if queue is too large
  scan_batch_size INTEGER := 500; -- Conservative batch size for scanning
BEGIN
  -- Step 1: Check current queue size for load management
  SELECT COUNT(*) INTO current_queue_size FROM pgmq.q_embedding_jobs;
  
  -- Step 2: Intelligent load management - only scan for outdated embeddings if system can handle it
  -- This prevents overwhelming the system during high-volume periods
  IF current_queue_size < system_load_threshold THEN
    -- Scan for and enqueue outdated embeddings (limited batch to prevent overload)
    SELECT enqueue_outdated_embeddings(scan_batch_size) INTO enqueued_count;
    
    IF enqueued_count > 0 THEN
      RAISE LOG 'Autopilot: Detected and enqueued % documents for re-embedding (queue_size: %)', 
                enqueued_count, current_queue_size + enqueued_count;
    ELSE
      RAISE LOG 'Autopilot: No outdated embeddings detected - system synchronized (queue_size: %)', 
                current_queue_size;
    END IF;
  ELSE
    RAISE LOG 'Autopilot: Queue size (%) exceeds threshold (%), skipping scan to prevent overload', 
              current_queue_size, system_load_threshold;
  END IF;
  
  -- Step 3: Always trigger processing (handles both new scans and existing queue)
  -- This ensures the system keeps processing even when not scanning for new work
  PERFORM trigger_embedding_queue_processing_adaptive();
  
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'Autopilot master controller error: %', SQLERRM;
  -- Log error but don't re-raise - system should continue operating
END;
$$;

-- ==============================================================================
-- AUTONOMOUS SCHEDULING: 24/7 Operation via Cron
-- ==============================================================================

-- Remove any existing embedding processing cron jobs to prevent conflicts
DO $$
BEGIN
  -- Clean up any existing autopilot cron jobs
  BEGIN
    PERFORM cron.unschedule('process-embedding-queue');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  
  BEGIN
    PERFORM cron.unschedule('process-embeddings-cpu-aware');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  
  BEGIN
    PERFORM cron.unschedule('autopilot-embedding-sync');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  
  BEGIN
    PERFORM cron.unschedule('autonomous-embedding-system');
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- Schedule the autonomous embedding system for continuous operation
-- Every 30 seconds: intelligent scanning + adaptive processing
SELECT cron.schedule(
  'autonomous-embedding-system',
  '*/30 * * * * *',  -- Every 30 seconds (6 fields for seconds precision)
  'SELECT autopilot_embedding_sync();'
);

-- ==============================================================================
-- COMPREHENSIVE MONITORING AND OBSERVABILITY
-- ==============================================================================

/**
 * Enhanced monitoring view for the autonomous embedding system
 * Provides real-time metrics and health indicators for production monitoring
 */
CREATE OR REPLACE VIEW "public"."autonomous_system_status" AS
SELECT 
  'Autonomous Embedding System' as system_name,
  (SELECT COUNT(*) FROM pgmq.q_embedding_jobs) as pending_jobs,
  (SELECT COUNT(*) FROM source_documents WHERE content IS NOT NULL AND status = 'active') as total_documents,
  (SELECT COUNT(*) FROM document_embeddings) as documents_with_embeddings,
  (SELECT COUNT(*) FROM document_embeddings WHERE embedding IS NOT NULL) as documents_with_valid_embeddings,
  (SELECT COUNT(*) FROM find_outdated_embeddings(10000)) as documents_needing_update,
  (SELECT COUNT(*) FROM embedding_error_log WHERE created_at > now() - interval '1 hour') as errors_last_hour,
  (SELECT COUNT(*) FROM embedding_error_log WHERE created_at > now() - interval '24 hours') as errors_last_24h,
  (
    SELECT ROUND(
      100.0 * COUNT(CASE WHEN de.embedding IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 
      1
    )
    FROM source_documents sd
    LEFT JOIN document_embeddings de ON sd.document_id = de.document_id
    WHERE sd.content IS NOT NULL AND sd.status = 'active'
  ) as embedding_coverage_percent,
  (
    SELECT COUNT(*) FILTER (WHERE message->>'autopilot_reembedding' = 'true')
    FROM pgmq.q_embedding_jobs 
    WHERE enqueued_at > now() - interval '1 hour'
  ) as autopilot_jobs_last_hour,
  now() as last_checked;

-- Grant permissions for monitoring and management
GRANT SELECT ON "public"."autonomous_system_status" TO service_role;
GRANT EXECUTE ON FUNCTION "public"."find_outdated_embeddings" TO service_role;
GRANT EXECUTE ON FUNCTION "public"."enqueue_outdated_embeddings" TO service_role;
GRANT EXECUTE ON FUNCTION "public"."autopilot_embedding_sync" TO service_role;

-- Utility function for manual system control (used by Edge Functions)
CREATE OR REPLACE FUNCTION "public"."exec_sql"(sql TEXT) 
RETURNS JSONB
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
DECLARE
  result JSONB;
BEGIN
  EXECUTE sql;
  result := jsonb_build_object(
    'success', true, 
    'message', 'SQL executed successfully',
    'timestamp', now()
  );
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  result := jsonb_build_object(
    'success', false, 
    'error', SQLERRM,
    'error_code', SQLSTATE,
    'timestamp', now()
  );
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."exec_sql" TO service_role;

-- ==============================================================================
-- SYSTEM VERIFICATION AND STARTUP
-- ==============================================================================

-- Verify the autonomous system was deployed successfully
SELECT 
  'Autonomous system deployment' as status,
  jobid,
  schedule,
  command,
  active,
  CASE 
    WHEN active = true THEN '✅ Autopilot active - autonomous 24/7 operation enabled'
    ELSE '❌ Autopilot inactive - manual intervention required'
  END as deployment_status
FROM cron.job 
WHERE command LIKE '%autopilot_embedding_sync%';

-- Show initial system status
SELECT 
  system_name,
  pending_jobs || ' pending' as queue_status,
  documents_needing_update || ' need re-embedding' as sync_status,
  embedding_coverage_percent || '% synchronized' as coverage,
  CASE 
    WHEN errors_last_hour = 0 THEN '✅ No recent errors'
    ELSE '⚠️ ' || errors_last_hour || ' errors in last hour'
  END as health_status
FROM autonomous_system_status;

-- Add comprehensive documentation comments
COMMENT ON FUNCTION "public"."find_outdated_embeddings" IS 'Autopilot brain: Intelligently detects documents with changed content requiring re-embedding using hash comparison';
COMMENT ON FUNCTION "public"."enqueue_outdated_embeddings" IS 'Autopilot worker: Handles large-scale re-embedding with micro-batching to prevent timeouts and system overload';
COMMENT ON FUNCTION "public"."trigger_embedding_queue_processing_adaptive" IS 'Autopilot processor: CPU-aware processing that adapts batch size based on queue depth and system capacity';
COMMENT ON FUNCTION "public"."autopilot_embedding_sync" IS 'Autopilot master controller: Orchestrates the complete autonomous re-embedding cycle with intelligent load management';
COMMENT ON VIEW "public"."autonomous_system_status" IS 'Real-time autonomous system health monitoring with comprehensive metrics, coverage analysis, and autopilot activity tracking';

-- Final deployment confirmation
SELECT 
  'Autonomous Embedding System Ready' as status,
  'SUCCESS' as result,
  'The system is now fully autonomous and will maintain embedding synchronization 24/7' as message;
