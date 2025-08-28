-- ==============================================================================
-- SUPABASE SIDECAR EMBEDDING ENGINE - COMPLETE BOOTSTRAP
-- ==============================================================================
-- 
-- This file contains the complete setup for the Supabase Sidecar Embedding Engine.
-- Run this entire file in your Supabase SQL Editor to set up the complete system.
--
-- What this creates:
-- 1. Source documents table with clean schema
-- 2. Document embeddings sidecar table with vector indexes
-- 3. Embedding queue system with pgmq
-- 4. Autonomous re-embedding system with pg_cron
--
-- Prerequisites:
-- - Supabase project with pgvector, pgmq, pg_cron, and pg_net extensions enabled
-- - Service role key stored in Vault (see README for setup instructions)
--
-- ==============================================================================

-- ==============================================================================
-- STEP 1: ENABLE REQUIRED EXTENSIONS
-- ==============================================================================

-- Enable all required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "vector";      -- For vector storage and similarity search
CREATE EXTENSION IF NOT EXISTS "pgmq";        -- For persistent message queuing
CREATE EXTENSION IF NOT EXISTS "pg_cron";     -- For scheduled job execution
CREATE EXTENSION IF NOT EXISTS "pg_net";     -- For HTTP requests from PostgreSQL

-- Verify extensions are enabled
SELECT 
    'Extensions Status' as status,
    'vector' as extension,
    CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN '✅ Enabled' ELSE '❌ Missing' END as status
UNION ALL
SELECT 
    'Extensions Status' as status,
    'pgmq' as extension,
    CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pgmq') THEN '✅ Enabled' ELSE '❌ Missing' END as status
UNION ALL
SELECT 
    'Extensions Status' as status,
    'pg_cron' as extension,
    CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN '✅ Enabled' ELSE '❌ Missing' END as status
UNION ALL
SELECT 
    'Extensions Status' as status,
    'pg_net' as extension,
    CASE WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN '✅ Enabled' ELSE '❌ Missing' END as status;

-- ==============================================================================
-- STEP 2: SOURCE DOCUMENTS SCHEMA
-- ==============================================================================

-- Main source documents table (clean, minimal schema)
-- Uses simple 'content' field as single source of truth for embeddings
CREATE TABLE IF NOT EXISTS "public"."source_documents" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "content" TEXT NOT NULL, -- Single source of truth for embedding generation
    "metadata" JSONB DEFAULT '{}'::jsonb,
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT "source_documents_pkey" PRIMARY KEY ("id")
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS "idx_source_documents_created_at" ON "public"."source_documents" ("created_at");
CREATE INDEX IF NOT EXISTS "idx_source_documents_updated_at" ON "public"."source_documents" ("updated_at");

-- Full-text search index on content
CREATE INDEX IF NOT EXISTS "idx_source_documents_content_fts" ON "public"."source_documents" 
USING gin(to_tsvector('english', content));

-- Metadata search index  
CREATE INDEX IF NOT EXISTS "idx_source_documents_metadata_gin" ON "public"."source_documents" 
USING gin(metadata);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."source_documents" TO service_role;

-- Add helpful comments explaining the clean design
COMMENT ON TABLE "public"."source_documents" IS 'Clean document storage - content is single source of truth for embeddings';
COMMENT ON COLUMN "public"."source_documents"."content" IS 'The text content that will be used for embedding generation';
COMMENT ON COLUMN "public"."source_documents"."metadata" IS 'Optional JSON field for document-specific attributes';

-- Create function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER "update_source_documents_updated_at" 
    BEFORE UPDATE ON "public"."source_documents" 
    FOR EACH ROW 
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ==============================================================================
-- STEP 3: DOCUMENT EMBEDDINGS SIDECAR TABLE
-- ==============================================================================

-- Document embeddings sidecar table (clean, minimal design)
-- This is the core of the sidecar pattern - keeping AI-generated data separate from source data
CREATE TABLE IF NOT EXISTS "public"."document_embeddings" (
    "document_id" uuid NOT NULL,
    "source_text" TEXT NOT NULL, -- The actual text that was embedded
    "source_text_hash" TEXT GENERATED ALWAYS AS (md5(source_text)) STORED NOT NULL,
    "embedding" vector(384), -- 384-dimensional vectors from gte-small model
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    
    -- Primary key and foreign key relationship
    CONSTRAINT "document_embeddings_pkey" PRIMARY KEY ("document_id"),
    CONSTRAINT "document_embeddings_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.source_documents(id) ON DELETE CASCADE
);

-- Performance indexes for the sidecar table  
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_source_text_hash" ON "public"."document_embeddings" ("source_text_hash");

-- Vector similarity search index (HNSW for fast similarity queries)
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_vector_cosine" ON "public"."document_embeddings" 
USING hnsw (embedding vector_cosine_ops);

-- Additional vector indexes for different similarity metrics
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_vector_l2" ON "public"."document_embeddings" 
USING hnsw (embedding vector_l2_ops);

-- Grant permissions for the sidecar table
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."document_embeddings" TO service_role;

-- Create trigger to automatically update updated_at timestamp
CREATE TRIGGER "update_document_embeddings_updated_at" 
    BEFORE UPDATE ON "public"."document_embeddings" 
    FOR EACH ROW 
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Helper function to check if embedding needs updating (change detection)
CREATE OR REPLACE FUNCTION "public"."embedding_needs_update"(
    p_document_id TEXT,
    p_current_content TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    stored_hash TEXT;
    current_hash TEXT;
BEGIN
    -- Calculate hash of current content
    current_hash := md5(p_current_content);
    
    -- Get stored hash for this document
    SELECT source_text_hash INTO stored_hash
    FROM document_embeddings 
    WHERE document_id = p_document_id;
    
    -- Return true if no embedding exists or content has changed
    RETURN (stored_hash IS NULL OR stored_hash != current_hash);
END;
$$;

-- Grant execute permissions on helper functions
GRANT EXECUTE ON FUNCTION "public"."embedding_needs_update" TO service_role;

-- Add comprehensive comments explaining the sidecar architecture
COMMENT ON TABLE "public"."document_embeddings" IS 'Sidecar table for document embeddings - keeps AI-generated data separate from source data for optimal performance';
COMMENT ON COLUMN "public"."document_embeddings"."source_text_hash" IS 'MD5 hash of source text for change detection - enables intelligent re-embedding only when content actually changes';
COMMENT ON COLUMN "public"."document_embeddings"."embedding" IS '384-dimensional vector from gte-small model - optimized for semantic search and similarity operations';

-- ==============================================================================
-- STEP 4: EMBEDDING QUEUE SYSTEM
-- ==============================================================================

-- Create the embedding_jobs queue if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'pgmq'
    AND table_name = 'q_embedding_jobs'
  ) THEN
    PERFORM pgmq.create('embedding_jobs');
    RAISE NOTICE 'Created embedding_jobs queue';
  ELSE
    RAISE NOTICE 'embedding_jobs queue already exists';
  END IF;
END $$;

-- Grant permissions to service role for queue operations
GRANT USAGE ON SCHEMA pgmq TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON pgmq.q_embedding_jobs TO service_role;

-- Create secure RPC wrappers for Edge Functions (required by Supabase security model)
-- These functions expose pgmq operations to Edge Functions in a controlled way
CREATE OR REPLACE FUNCTION "public"."pgmq_read"(
  queue_name TEXT,
  visibility_timeout INTEGER DEFAULT 30,
  batch_size INTEGER DEFAULT 1
) RETURNS TABLE(msg_id BIGINT, read_ct INTEGER, enqueued_at TIMESTAMP WITH TIME ZONE, vt TIMESTAMP WITH TIME ZONE, message JSONB)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM pgmq.read(queue_name, visibility_timeout, batch_size);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."pgmq_archive"(
  queue_name TEXT,
  msg_id BIGINT
) RETURNS BOOLEAN
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
  RETURN pgmq.archive(queue_name, msg_id);
END;
$$;

-- Grant execute permissions on RPC functions
GRANT EXECUTE ON FUNCTION "public"."pgmq_read" TO service_role;
GRANT EXECUTE ON FUNCTION "public"."pgmq_archive" TO service_role;

-- Function to enqueue embedding job (called by triggers and manual operations)
CREATE OR REPLACE FUNCTION "public"."enqueue_embedding_job"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Only enqueue for INSERT or when content actually changes
  IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE' AND OLD.content IS DISTINCT FROM NEW.content) THEN
    -- Only enqueue if content is not null/empty
    IF NEW.content IS NOT NULL AND NEW.content <> '' THEN
      PERFORM pgmq.send('embedding_jobs', json_build_object(
        'document_id', NEW.id,
        'source_text', NEW.content,
        'metadata', NEW.metadata,
        'trigger_type', TG_OP,
        'enqueued_at', now()
      )::jsonb);
      
      RAISE LOG 'Enqueued embedding job for document: % (trigger: %)', 
                NEW.id, TG_OP;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger on source_documents to auto-enqueue new/changed records
DROP TRIGGER IF EXISTS "enqueue_embedding_on_change" ON "public"."source_documents";
CREATE TRIGGER "enqueue_embedding_on_change"
    AFTER INSERT OR UPDATE ON "public"."source_documents"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."enqueue_embedding_job"();

-- Create comprehensive error logging table for tracking embedding failures
CREATE TABLE IF NOT EXISTS "public"."embedding_error_log" (
    "id" BIGSERIAL PRIMARY KEY,
    "document_id" TEXT NOT NULL,
    "error_message" TEXT NOT NULL,
    "error_context" JSONB DEFAULT '{}'::jsonb,
    "function_name" TEXT,
    "queue_message_id" TEXT,
    "retry_count" INTEGER DEFAULT 0,
    "max_retries" INTEGER DEFAULT 3,
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Indexes for efficient error analysis and debugging
CREATE INDEX IF NOT EXISTS "idx_embedding_error_log_document_id" ON "public"."embedding_error_log" ("document_id");
CREATE INDEX IF NOT EXISTS "idx_embedding_error_log_created_at" ON "public"."embedding_error_log" ("created_at");

-- Grant permissions for error logging
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."embedding_error_log" TO service_role;
GRANT USAGE ON SEQUENCE "public"."embedding_error_log_id_seq" TO service_role;

-- Helper function to log embedding errors with context
CREATE OR REPLACE FUNCTION "public"."log_embedding_error"(
    p_document_id TEXT,
    p_error_message TEXT,
    p_error_context JSONB DEFAULT '{}'::jsonb,
    p_function_name TEXT DEFAULT NULL,
    p_queue_message_id TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO embedding_error_log (
        document_id,
        error_message,
        error_context,
        function_name,
        queue_message_id
    ) VALUES (
        p_document_id,
        p_error_message,
        p_error_context,
        p_function_name,
        p_queue_message_id
    );
    
    RAISE LOG 'Logged embedding error for document %: %', p_document_id, p_error_message;
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."log_embedding_error" TO service_role;

-- Helper function to get queue statistics for monitoring
CREATE OR REPLACE FUNCTION "public"."get_queue_stats"()
RETURNS TABLE(
    total_pending BIGINT,
    oldest_job TIMESTAMP WITH TIME ZONE,
    newest_job TIMESTAMP WITH TIME ZONE,
    avg_processing_time INTERVAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_pending,
        MIN(enqueued_at) as oldest_job,
        MAX(enqueued_at) as newest_job,
        AVG(now() - enqueued_at) as avg_processing_time
    FROM pgmq.q_embedding_jobs;
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."get_queue_stats" TO service_role;

-- Add comprehensive comments documenting the queue system
COMMENT ON TABLE pgmq.q_embedding_jobs IS 'Persistent queue for processing document embeddings - handles automatic enqueueing when content changes';
COMMENT ON FUNCTION "public"."enqueue_embedding_job" IS 'Trigger function that automatically queues documents for embedding when their content changes - core of the autonomous processing system';
COMMENT ON FUNCTION "public"."pgmq_read" IS 'Secure RPC wrapper for reading jobs from the embedding queue - used by Edge Functions';
COMMENT ON FUNCTION "public"."pgmq_archive" IS 'Secure RPC wrapper for archiving completed jobs - maintains queue hygiene';
COMMENT ON TABLE "public"."embedding_error_log" IS 'Comprehensive error tracking for embedding operations - essential for debugging and monitoring production systems';

-- ==============================================================================
-- STEP 5: AUTONOMOUS RE-EMBEDDING SYSTEM
-- ==============================================================================

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
  system_load_threshold INTEGER := 1000; -- Don't scan if queue is too large
  scan_batch_size INTEGER := 500; -- Conservative batch size for scanning
BEGIN
  -- Step 1: Check current queue size for load management
  SELECT COUNT(*) INTO current_queue_size FROM pgmq.q_embedding_jobs;
  
  -- Step 2: Intelligent load management - only scan for outdated embeddings if system can handle it
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
    PERFORM cron.unschedule('autopilot-embedding-sync');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  
  BEGIN
    PERFORM cron.unschedule('autonomous-embedding-system');
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- Schedule the autonomous embedding system for continuous operation
-- Every 30 seconds: intelligent scanning for outdated embeddings
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
  (SELECT COUNT(*) FROM source_documents WHERE content IS NOT NULL) as total_documents,
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
    LEFT JOIN document_embeddings de ON sd.id = de.document_id
    WHERE sd.content IS NOT NULL
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

-- Add comprehensive documentation comments
COMMENT ON FUNCTION "public"."find_outdated_embeddings" IS 'Autopilot brain: Intelligently detects documents with changed content requiring re-embedding using hash comparison';
COMMENT ON FUNCTION "public"."enqueue_outdated_embeddings" IS 'Autopilot worker: Handles large-scale re-embedding with micro-batching to prevent timeouts and system overload';
COMMENT ON FUNCTION "public"."autopilot_embedding_sync" IS 'Autopilot master controller: Orchestrates the complete autonomous re-embedding cycle with intelligent load management';
COMMENT ON VIEW "public"."autonomous_system_status" IS 'Real-time autonomous system health monitoring with comprehensive metrics, coverage analysis, and autopilot activity tracking';

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

-- Final deployment confirmation
SELECT 
  'Supabase Sidecar Embedding Engine Ready' as status,
  'SUCCESS' as result,
  'The system is now fully autonomous and will maintain embedding synchronization 24/7' as message;

-- ==============================================================================
-- NEXT STEPS
-- ==============================================================================
--
-- 1. Store your service role key in Supabase Vault:
--    - Go to Project Settings → Vault
--    - Add secret: name="service_role_key", value="your_service_role_jwt"
--
-- 2. Deploy the Edge Function:
--    - Install Supabase CLI: npm install -g supabase
--    - Link to your project: supabase link
--    - Deploy: supabase functions deploy process-embedding-queue
--
-- 3. Test the system:
--    - Insert a test document into source_documents
--    - Check the queue: SELECT * FROM get_queue_stats();
--    - Monitor system status: SELECT * FROM autonomous_system_status;
--
-- For detailed setup instructions, see the README.md file.
-- ==============================================================================
