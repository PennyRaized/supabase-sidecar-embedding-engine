// --- OFFICIAL SUPABASE PATTERN ---
// This Edge Function uses public RPC wrappers (pgmq_read, pgmq_archive) to interact with the embedding_jobs queue.
// Direct calls to pgmq extension functions are not available to Edge Functions for security reasons.
// See: https://supabase.com/blog/automatic-embeddings and Supabase docs for details.
//
// The required wrappers must be created in the public schema:
//   - pgmq_read(queue_name text, visibility_timeout integer, batch_size integer)
//   - pgmq_archive(queue_name text, msg_id bigint)
//
// These wrappers expose queue operations to Edge Functions in a secure, supported way.
// -----------------------------------
// NOTE: The following import is required for Supabase Edge Functions and is expected to be resolved in the Supabase environment. The linter error for this remote import can be safely ignored.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

async function logEmbeddingError(errorMessage: string, context: unknown, functionName: string, queueMessageId?: string) {
  const { error } = await supabase.from('embedding_error_log').insert([{
      error_message: errorMessage,
      context,
      function_name: functionName,
      queue_message_id: queueMessageId,
    }
  ]);
}

Deno.serve(async (req) => {
  console.log("🟢 Edge Function handler invoked");
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    let requestBody: { batch_size?: number; timeout_seconds?: number; queue_name?: string } = {};
    try {
      if (req.body) requestBody = await req.json();
    } catch {
      // No-op: If parsing fails, requestBody remains as default
    }

    const batchSize = requestBody.batch_size || 7;
    const maxProcessingTime = requestBody.timeout_seconds || 30;
    const queueName = requestBody.queue_name || 'embedding_jobs'; // Support both queues
    const startTime = Date.now();

    let processed = 0;
    let errors = 0;
    const errorDetails: string[] = [];
    const processedMsgIds: bigint[] = [];

    console.log(`🚀 Starting processing with batch_size=${batchSize}, timeout=${maxProcessingTime}s`);

    // Fetch a batch of messages from the queue at once
      const { data: messages, error: queueError } = await supabase.rpc(
        'pgmq_read',
        { 
          queue_name: queueName,
          visibility_timeout: 300,
        batch_size: batchSize
        }
      );

      if (queueError) {
      console.error('❌ Error getting messages from queue:', queueError);
      await logEmbeddingError(queueError.message ?? String(queueError), { queueError }, 'process-embedding-queue');
      return new Response(
        JSON.stringify({
          processed: 0,
          errors: 1,
          error_details: [queueError.message ?? String(queueError)],
          processing_time_seconds: 0,
          batch_size_used: batchSize,
          timestamp: new Date().toISOString()
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
      }

      if (!messages || messages.length === 0) {
        console.log('✅ No messages in queue - processing complete');
        return new Response(
          JSON.stringify({
            processed: 0,
            errors: 0,
            error_details: [],
            processing_time_seconds: (Date.now() - startTime) / 1000,
            batch_size_used: batchSize,
            timestamp: new Date().toISOString()
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      console.log(`📦 Processing ${messages.length} messages from queue`);

      // Process each message
      for (const message of messages) {
        const { msg_id, message: messageData } = message;
        
        const isDocumentChunk =  messageData.chunk_id;
        const isCompanyEmbedding = queueName === 'embedding_jobs' || messageData.company_id;
        
        try {
          if (isDocumentChunk) {
            // Process document chunk embedding
            const { chunk_id, document_id, chunk_text } = messageData;
            
            if (!chunk_id || !document_id || !chunk_text) {
              console.error('❌ Invalid document chunk message format: missing required fields. Archiving message.');
              await logEmbeddingError('Invalid document chunk message format: missing required fields', { message }, 'process-embedding-queue', msg_id);
              if (msg_id) await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
              errors++;
              continue;
            }

            // Check if embedding already exists
            const { data: existingChunk, error: checkError } = await supabase
              .from('document_chunks')
              .select('embedding')
              .eq('id', chunk_id)
              .single();

            if (!checkError && existingChunk?.embedding) {
              console.log(`⏭️ Skipping chunk ${chunk_id} - embedding already exists`);
              if (msg_id) await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
              processed++;
              processedMsgIds.push(msg_id);
              continue;
            }

            // Generate embedding for document chunk
            if (typeof Supabase === 'undefined' || !Supabase.ai || !Supabase.ai.Session) {
              throw new Error('Supabase AI embedding API is not available in this Edge Function environment.');
            }
            const session = new Supabase.ai.Session('gte-small');
            const truncatedText = chunk_text.length > 2000 ? chunk_text.substring(0, 2000) + '...' : chunk_text;
            const embedding = await session.run(truncatedText, { mean_pool: true, normalize: true });
            
            if (!embedding || !Array.isArray(embedding) || embedding.length !== 384) {
              throw new Error(`Generated embedding is invalid. Expected 384-dimensional array, got: ${embedding ? embedding.length : 'null'}`);
            }

            // Update document_chunks table with the new embedding
            const { error: updateError } = await supabase
              .from('document_chunks')
              .update({ embedding })
              .eq('id', chunk_id);

            if (updateError) {
              throw new Error(`Failed to update document chunk: ${updateError.message}`);
            }

            console.log(`✅ Successfully processed document chunk: ${chunk_id}`);
            
          } else if (isCompanyEmbedding) {
            // Process company embedding
            const { company_id, source_text } = messageData;
            
            if (!company_id || !source_text) {
              console.error('❌ Invalid company embedding message format: missing required fields. Archiving message.');
              await logEmbeddingError('Invalid company embedding message format: missing required fields', { message }, 'process-embedding-queue', msg_id);
              if (msg_id) await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
              errors++;
              continue;
            }

            // Check if this exact content has already been processed
            const sourceTextHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source_text));
            const hashArray = Array.from(new Uint8Array(sourceTextHash));
            const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

            const { data: existingEmbedding, error: checkError } = await supabase
              .from('company_embeddings')
              .select('source_text_hash')
              .eq('company_id', company_id)
              .single();

            if (!checkError && existingEmbedding?.source_text_hash === hashHex) {
              console.log(`⏭️ Skipping company ${company_id} - content unchanged`);
              if (msg_id) await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
              processed++;
              processedMsgIds.push(msg_id);
              continue;
            }

            // Generate embedding for company
            if (typeof Supabase === 'undefined' || !Supabase.ai || !Supabase.ai.Session) {
              throw new Error('Supabase AI embedding API is not available in this Edge Function environment.');
            }
            const session = new Supabase.ai.Session('gte-small');
            const truncatedText = source_text.length > 2000 ? source_text.substring(0, 2000) + '...' : source_text;
            const embedding = await session.run(truncatedText, { mean_pool: true, normalize: true });
            
            if (!embedding || !Array.isArray(embedding) || embedding.length !== 384) {
              throw new Error(`Generated embedding is invalid. Expected 384-dimensional array, got: ${embedding ? embedding.length : 'null'}`);
            }

            // Update or insert into company_embeddings table (sidecar pattern)
            const { error: upsertError } = await supabase
              .from('company_embeddings')
              .upsert({
                company_id,
                source_text,
                embedding,
                updated_at: new Date().toISOString()
              }, {
                onConflict: 'company_id'
              });

            if (upsertError) {
              throw new Error(`Failed to upsert company embedding: ${upsertError.message}`);
            }

            console.log(`✅ Successfully processed company: ${company_id}`);
          }

          // Archive the successfully processed message
          if (msg_id) {
            const { error: archiveError } = await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
            if (archiveError) {
              console.warn(`⚠️ Warning: Failed to archive message ${msg_id}: ${archiveError.message}`);
            }
          }
          
          processed++;
          processedMsgIds.push(msg_id);

        } catch (processingError: any) {
          console.error(`❌ Error processing message ${msg_id}:`, processingError);
          await logEmbeddingError(processingError.message, { message, processingError }, 'process-embedding-queue', msg_id);
          errorDetails.push(`Message ${msg_id}: ${processingError.message}`);
          errors++;
          
          // Archive failed messages to prevent infinite retries
          if (msg_id) {
            const { error: archiveError } = await supabase.rpc('pgmq_archive', { queue_name: queueName, msg_id });
            if (archiveError) {
              console.warn(`⚠️ Warning: Failed to archive failed message ${msg_id}: ${archiveError.message}`);
            }
          }
        }

        // Check timeout
        if ((Date.now() - startTime) / 1000 > maxProcessingTime) {
          console.log(`⏰ Timeout reached (${maxProcessingTime}s) - stopping processing`);
          break;
        }
      }

    const processingTimeSeconds = (Date.now() - startTime) / 1000;
    console.log(`🏁 Processing complete: ${processed} processed, ${errors} errors in ${processingTimeSeconds.toFixed(2)}s`);

    // Self-invoke if there are more messages and we haven't hit timeout
    if (processed > 0 && processingTimeSeconds < maxProcessingTime * 0.8) {
      console.log('🔄 Self-invoking to continue processing...');
      
      // Use fetch to make a non-blocking call to self
      fetch(req.url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
      }).catch(error => {
        console.log('⚠️ Self-invocation failed (non-critical):', error);
      });
    }

    return new Response(
      JSON.stringify({
        processed,
        errors,
        error_details: errorDetails,
        processing_time_seconds: processingTimeSeconds,
        batch_size_used: batchSize,
        processed_message_ids: processedMsgIds,
        timestamp: new Date().toISOString()
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: any) {
    console.error('💥 Unexpected error in embedding queue processor:', error);
    await logEmbeddingError(error.message, { error }, 'process-embedding-queue');
    
    return new Response(
      JSON.stringify({
        processed: 0,
        errors: 1,
        error_details: [error.message],
        processing_time_seconds: 0,
        batch_size_used: 0,
        timestamp: new Date().toISOString()
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});


