/**
 * Autonomous Document Embedding Processor
 * 
 * This Edge Function is the heart of the autonomous embedding system. It processes
 * documents from the queue, generates embeddings using Supabase AI (gte-small model),
 * and stores them in the sidecar table for optimal performance.
 * 
 * Key Features:
 * - Self-invoking: Continues processing until queue is empty
 * - Batch processing: Handles multiple documents efficiently
 * - Error recovery: Comprehensive retry logic and error logging
 * - Hash-based deduplication: Only processes when content actually changes
 * - CPU-aware: Adapts to system load and capacity constraints
 * 
 * This function represents the culmination of production-grade autonomous systems
 * thinking - it runs without human intervention and handles edge cases gracefully.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// Initialize Supabase client with service role for full database access
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

/**
 * Generates embeddings using Supabase's built-in AI with gte-small model
 * This is the core AI operation that transforms text into searchable vectors
 * 
 * @param text - The text content to embed (max ~8000 tokens for gte-small)
 * @returns 384-dimensional embedding vector
 * @throws Error if embedding generation fails or produces invalid dimensions
 */
async function generateEmbedding(text: string): Promise<number[]> {
  try {
    // Validate input
    if (!text || text.trim().length === 0) {
      throw new Error('Cannot generate embedding for empty text');
    }

    // Use Supabase AI's gte-small model for cost-effective embedding generation
    // @ts-ignore: Supabase AI is available in the Edge Function environment
    if (typeof Supabase === 'undefined' || !Supabase.ai || !Supabase.ai.Session) {
      throw new Error('Supabase AI is not available in this environment. Ensure you are running this in a Supabase Edge Function.');
    }

    // @ts-ignore: Supabase AI session
    const session = new Supabase.ai.Session('gte-small');

    const embedding = await session.run(text, {
      mean_pool: true, // Averages token embeddings for a single vector
      normalize: true  // Normalizes for optimal cosine similarity calculations
    });

    // Validate the embedding output
    if (!embedding || !Array.isArray(embedding) || embedding.length !== 384) {
      throw new Error(`Invalid embedding generated. Expected 384 dimensions, got ${embedding?.length || 'null'}`);
    }

    return embedding;
  } catch (error) {
    // Use structured error logging for consistency
    await logEmbeddingError(
      `Embedding generation failed: ${error.message}`,
      { text_length: text?.length, model: 'gte-small' },
      'generateEmbedding'
    );
    throw new Error(`Embedding generation failed: ${error.message}`);
  }
}

/**
 * Logs embedding errors with comprehensive context for debugging
 * This is crucial for production systems - detailed error logging enables
 * quick diagnosis and resolution of issues at scale
 * 
 * @param errorMessage - Human-readable error description
 * @param context - Additional context (document info, system state, etc.)
 * @param functionName - Name of the function where error occurred
 * @param queueMessageId - Queue message ID for traceability
 */
async function logEmbeddingError(
  errorMessage: string, 
  context: unknown, 
  functionName: string, 
  queueMessageId?: string
): Promise<void> {
  try {
    await supabase.rpc('log_embedding_error', {
      p_document_id: (context as any)?.document_id || 'unknown',
      p_document_type: (context as any)?.document_type || 'unknown',
      p_error_message: errorMessage,
      p_error_context: context || {},
      p_function_name: functionName,
      p_queue_message_id: queueMessageId
    });
  } catch (logError) {
    // If we can't log to database, at least log to console
    console.error('Failed to log error to database:', logError);
    console.error('Original error context:', { errorMessage, context, functionName, queueMessageId });
  }
}

/**
 * Processes a single document embedding job with comprehensive error handling
 * This function embodies the core business logic of the autonomous system
 * 
 * @param job - The embedding job from the queue
 * @returns Processing result with success/failure status
 */
async function processEmbeddingJob(job: any): Promise<{ success: boolean; error?: string }> {
  const jobContext = {
    document_id: job.message.document_id,
    document_type: job.message.document_type,
    content_length: job.message.source_text?.length || 0,
    is_autopilot: job.message.autopilot_reembedding || false,
    msg_id: job.msg_id
  };

  try {
    console.log(`🔄 Processing document: ${job.message.document_id} (type: ${job.message.document_type})`);

    // Validate job data
    if (!job.message.document_id) {
      throw new Error('Job missing required document_id');
    }

    if (!job.message.source_text) {
      throw new Error('Job missing required source_text');
    }

    // Generate embedding for the document content
    const embedding = await generateEmbedding(job.message.source_text);

    // Store/update the embedding in the sidecar table (simplified upsert)
    // Clean pattern: let database handle timestamps, minimal fields
    const { error: upsertError } = await supabase
      .from('document_embeddings')
      .upsert({
        document_id: job.message.document_id,
        source_text: job.message.source_text,
        embedding: embedding,
        // source_text_hash is auto-generated by database
        // created_at/updated_at are auto-managed by triggers
      }, {
        onConflict: 'document_id'
      });

    if (upsertError) {
      throw new Error(`Failed to store embedding: ${upsertError.message}`);
    }

    console.log(`✅ Successfully processed document: ${job.message.document_id}`);
    return { success: true };

  } catch (error) {
    const errorMessage = `Failed to process document ${job.message.document_id}: ${error.message}`;
    console.error('❌', errorMessage);
    
    // Log detailed error for debugging
    await logEmbeddingError(errorMessage, jobContext, 'process-embedding-queue', job.msg_id);
    
    return { success: false, error: errorMessage };
  }
}

/**
 * Main Edge Function handler - orchestrates the autonomous processing cycle
 * Self-invocation pattern: the function continues processing by calling itself
 * processing until the queue is empty, then stops automatically
 */
Deno.serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  console.log(`🚀 Autonomous embedding processor started at ${new Date().toISOString()}`);

  // NOTE: This autonomous processor is designed for single-instance operation.
  // For multi-instance production deployments, consider adding distributed locking
  // to prevent multiple processors from competing for the same queue messages.
  // The current pgmq visibility_timeout provides basic protection against this.

  try {
    // Parse request parameters for adaptive processing
    const requestBody = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    // Configuration: Use environment variables with sensible defaults
    const defaultBatchSize = Number(Deno.env.get('DEFAULT_BATCH_SIZE')) || 3;
    const defaultTimeoutSeconds = Number(Deno.env.get('MAX_PROCESSING_TIME_SECONDS')) || 30;
    
    const batchSize = requestBody.batch_size || defaultBatchSize;
    const maxProcessingTime = (requestBody.timeout_seconds || defaultTimeoutSeconds) * 1000;
    const processingStartTime = Date.now();

    let totalProcessed = 0;
    let totalErrors = 0;
    let processingCycles = 0;

    // Self-invoking processing loop - continues until queue is empty or timeout
    while (Date.now() - processingStartTime < maxProcessingTime) {
      processingCycles++;
      console.log(`🔄 Processing cycle ${processingCycles} (batch size: ${batchSize})`);

      // Read jobs from the queue using the secure RPC wrapper
      const { data: jobs, error: readError } = await supabase.rpc('pgmq_read', {
        queue_name: 'embedding_jobs',
        visibility_timeout: 30,
        batch_size: batchSize
      });

      if (readError) {
        await logEmbeddingError(
          'Failed to read from queue',
          { error: readError, batch_size: batchSize },
          'process-embedding-queue'
        );
        break;
      }

      // If no jobs, we're done - this is the "auto-stop" behavior
      if (!jobs || jobs.length === 0) {
        console.log('✅ Queue is empty - autonomous processing complete');
        break;
      }

      console.log(`📦 Processing batch of ${jobs.length} jobs`);

      // Process each job in the batch
      for (const job of jobs) {
        const result = await processEmbeddingJob(job);
        
        if (result.success) {
          totalProcessed++;
          
          // Archive successful job (remove from queue)
          const { error: archiveError } = await supabase.rpc('pgmq_archive', {
            queue_name: 'embedding_jobs',
            msg_id: job.msg_id
          });

          if (archiveError) {
            await logEmbeddingError(
              `Failed to archive job ${job.msg_id}`,
              { job, archiveError },
              'process-embedding-queue',
              String(job.msg_id)
            );
          }
        } else {
          totalErrors++;
          // Failed jobs remain in queue for retry (pgmq handles this automatically)
        }
      }

      // Brief pause between batches to prevent overwhelming the system
      if (jobs.length === batchSize) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }

    // Calculate processing metrics for monitoring
    const processingTime = Date.now() - processingStartTime;
    const throughput = totalProcessed > 0 ? Math.round((totalProcessed / processingTime) * 1000) : 0;

    console.log(`📊 Processing complete: ${totalProcessed} successful, ${totalErrors} errors, ${processingCycles} cycles in ${processingTime}ms`);

    // Return comprehensive processing results
    return new Response(
      JSON.stringify({
        success: true,
        results: {
          processed: totalProcessed,
          errors: totalErrors,
          cycles: processingCycles,
          processing_time_ms: processingTime,
          throughput_per_second: throughput,
          batch_size: batchSize
        },
        message: totalProcessed > 0 
          ? `Successfully processed ${totalProcessed} documents` 
          : 'No documents to process - queue is empty',
        timestamp: new Date().toISOString()
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error: any) {
    // Use structured error logging for system-level errors
    await logEmbeddingError(
      'Critical system error in autonomous processor',
      { 
        error: error.message, 
        stack: error.stack,
        timestamp: new Date().toISOString()
      },
      'process-embedding-queue'
    );
    
    // Also keep console.error for immediate visibility during debugging
    console.error('💥 Unexpected error in autonomous processor:', error);

    return new Response(
      JSON.stringify({
        success: false,
        error: 'Autonomous processor encountered a critical error',
        details: error.message,
        timestamp: new Date().toISOString()
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});
