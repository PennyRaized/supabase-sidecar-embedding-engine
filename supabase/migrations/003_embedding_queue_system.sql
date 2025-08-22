-- Embedding Queue System
-- Generic queue infrastructure for processing document embeddings asynchronously
-- Handles automatic enqueueing when documents are created or content changes

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
    -- Only enqueue if content is not null/empty and document is active
    IF NEW.content IS NOT NULL AND NEW.content <> '' AND NEW.status = 'active' THEN
      PERFORM pgmq.send('embedding_jobs', json_build_object(
        'document_id', NEW.document_id,
        'document_type', NEW.document_type,
        'source_text', NEW.content,
        'title', NEW.title,
        'metadata', NEW.metadata,
        'trigger_type', TG_OP,
        'enqueued_at', now()
      )::jsonb);
      
      RAISE LOG 'Enqueued embedding job for document: % (type: %, trigger: %)', 
                NEW.document_id, NEW.document_type, TG_OP;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."enqueue_embedding_job"() OWNER TO "postgres";

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
    "document_type" TEXT,
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
CREATE INDEX IF NOT EXISTS "idx_embedding_error_log_document_type" ON "public"."embedding_error_log" ("document_type");
CREATE INDEX IF NOT EXISTS "idx_embedding_error_log_created_at" ON "public"."embedding_error_log" ("created_at");
CREATE INDEX IF NOT EXISTS "idx_embedding_error_log_function_name" ON "public"."embedding_error_log" ("function_name");

-- Grant permissions for error logging
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."embedding_error_log" TO service_role;
GRANT USAGE ON SEQUENCE "public"."embedding_error_log_id_seq" TO service_role;

-- Helper function to log embedding errors with context
CREATE OR REPLACE FUNCTION "public"."log_embedding_error"(
    p_document_id TEXT,
    p_document_type TEXT,
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
        document_type,
        error_message,
        error_context,
        function_name,
        queue_message_id
    ) VALUES (
        p_document_id,
        p_document_type,
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
COMMENT ON FUNCTION "public"."log_embedding_error" IS 'Standardized error logging with context - provides detailed debugging information for failed embedding operations';
COMMENT ON FUNCTION "public"."get_queue_stats" IS 'Real-time queue monitoring and performance metrics - essential for production observability';

-- Verify queue setup and trigger installation
SELECT 
  'Queue setup verification' as status,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'pgmq' AND table_name = 'q_embedding_jobs') as queue_exists,
  EXISTS(SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'enqueue_embedding_on_change') as trigger_exists,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'embedding_error_log') as error_log_exists;

-- Show initial queue statistics
SELECT 
  'Initial queue status' as status,
  total_pending,
  CASE 
    WHEN total_pending = 0 THEN 'Queue is empty and ready for processing'
    ELSE total_pending || ' jobs pending processing'
  END as queue_status
FROM get_queue_stats();


