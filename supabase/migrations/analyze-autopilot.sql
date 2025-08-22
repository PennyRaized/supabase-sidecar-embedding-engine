-- Autopilot Analysis and Management Script
-- Use this script to understand and control the autonomous re-embedding system

-- ==============================================================================
-- AUTOPILOT SYSTEM OVERVIEW
-- ==============================================================================

-- Get comprehensive autopilot status
SELECT 
  '🤖 AUTOPILOT SYSTEM STATUS' as section,
  system_name,
  pending_jobs || ' jobs pending' as queue_status,
  companies_needing_update || ' companies need re-embedding' as sync_status,
  embedding_coverage_percent || '% coverage' as data_quality,
  CASE 
    WHEN errors_last_hour = 0 THEN '✅ No recent errors'
    ELSE '⚠️ ' || errors_last_hour || ' errors in last hour'
  END as health_status
FROM autopilot_system_status;

-- ==============================================================================
-- DATA DRIFT ANALYSIS
-- ==============================================================================

-- Analyze what specific data has changed and needs re-embedding
SELECT 
  '📊 DATA DRIFT ANALYSIS' as section,
  COUNT(*) as outdated_companies,
  AVG(LENGTH(combined_text)) as avg_text_length,
  COUNT(*) FILTER (WHERE LENGTH(combined_text) > 2000) as large_documents,
  COUNT(*) FILTER (WHERE LENGTH(combined_text) < 500) as small_documents
FROM find_outdated_embeddings(1000);

-- Show sample of companies with outdated embeddings
SELECT 
  '🔍 SAMPLE OUTDATED COMPANIES' as section,
  company_id,
  LEFT(combined_text, 100) || '...' as text_preview,
  current_hash,
  stored_hash
FROM find_outdated_embeddings(10)
ORDER BY company_id
LIMIT 5;

-- ==============================================================================
-- CRON JOB MONITORING
-- ==============================================================================

-- Check autopilot cron job status
SELECT 
  '⏰ CRON JOB STATUS' as section,
  jobid,
  schedule as frequency,
  active as is_active,
  last_run,
  next_run,
  CASE 
    WHEN active = true THEN '✅ Running autonomously'
    ELSE '❌ Disabled - autopilot inactive'
  END as status
FROM cron.job 
WHERE command LIKE '%autopilot_embedding_sync%';

-- ==============================================================================
-- QUEUE ANALYSIS
-- ==============================================================================

-- Analyze current queue composition and autopilot activity
SELECT 
  '📋 QUEUE ANALYSIS' as section,
  COUNT(*) as total_jobs,
  COUNT(*) FILTER (WHERE message->>'autopilot_reembedding' = 'true') as autopilot_jobs,
  COUNT(*) FILTER (WHERE message->>'trigger_type' = 'INSERT') as new_document_jobs,
  COUNT(*) FILTER (WHERE message->>'trigger_type' = 'UPDATE') as update_jobs,
  MIN(enqueued_at) as oldest_job,
  MAX(enqueued_at) as newest_job
FROM pgmq.q_embedding_jobs;

-- ==============================================================================
-- ERROR ANALYSIS
-- ==============================================================================

-- Recent autopilot errors and patterns
SELECT 
  '⚠️ RECENT ERRORS' as section,
  COUNT(*) as error_count,
  function_name,
  LEFT(error_message, 100) || '...' as error_preview
FROM embedding_error_log 
WHERE created_at > now() - interval '24 hours'
GROUP BY function_name, LEFT(error_message, 100)
ORDER BY error_count DESC
LIMIT 5;

-- ==============================================================================
-- PERFORMANCE METRICS
-- ==============================================================================

-- Autopilot processing performance over time
SELECT 
  '📈 PERFORMANCE METRICS' as section,
  DATE_TRUNC('hour', created_at) as hour,
  COUNT(*) as embeddings_processed,
  COUNT(DISTINCT company_id) as unique_companies,
  ROUND(AVG(LENGTH(error_context->>'source_text'))) as avg_text_length
FROM embedding_error_log 
WHERE created_at > now() - interval '24 hours'
  AND function_name = 'process-embedding-queue'
GROUP BY DATE_TRUNC('hour', created_at)
ORDER BY hour DESC
LIMIT 24;

-- ==============================================================================
-- MANUAL CONTROL COMMANDS
-- ==============================================================================

-- Uncomment and run these commands for manual autopilot control:

-- Manual trigger autopilot sync (detects changes and processes)
-- SELECT autopilot_embedding_sync();

-- Manual bulk enqueue (for large-scale updates)
-- SELECT enqueue_outdated_embeddings(10000);

-- Force process queue (trigger immediate processing)
-- SELECT trigger_embedding_queue_processing_cpu_aware();

-- ==============================================================================
-- SYSTEM RECOMMENDATIONS
-- ==============================================================================

SELECT 
  '💡 SYSTEM RECOMMENDATIONS' as section,
  CASE 
    WHEN s.companies_needing_update > 1000 THEN 
      'Consider running manual bulk enqueue: SELECT enqueue_outdated_embeddings(10000);'
    WHEN s.pending_jobs > 500 THEN
      'Large queue detected. Monitor processing speed and consider scaling.'
    WHEN s.errors_last_hour > 10 THEN
      'High error rate detected. Check error logs and system health.'
    WHEN s.embedding_coverage_percent < 95 THEN
      'Low embedding coverage. Run autopilot sync: SELECT autopilot_embedding_sync();'
    ELSE
      '✅ System running optimally. Autopilot maintaining good synchronization.'
  END as recommendation
FROM autopilot_system_status s;

-- Final status summary
SELECT 
  '🎯 QUICK STATUS SUMMARY' as section,
  CASE 
    WHEN pending_jobs = 0 AND companies_needing_update = 0 THEN '🟢 Perfect Sync'
    WHEN pending_jobs < 100 AND companies_needing_update < 100 THEN '🟡 Minor Drift'
    WHEN pending_jobs < 1000 AND companies_needing_update < 1000 THEN '🟠 Moderate Drift'
    ELSE '🔴 Large Drift - Manual Intervention Recommended'
  END as system_status,
  embedding_coverage_percent || '% synchronized' as coverage,
  pending_jobs || ' jobs queued' as queue_info
FROM autopilot_system_status;


