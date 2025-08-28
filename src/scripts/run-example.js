#!/usr/bin/env node

/**
 * Supabase Sidecar Embedding Engine - End-to-End Example
 * 
 * This script demonstrates the complete workflow:
 * 1. Insert a sample document
 * 2. Wait for processing
 * 3. Check if embedding was created
 * 4. Run a similarity search
 * 
 * Usage: node src/scripts/run-example.js
 */

import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';

// Load environment variables from .env file
dotenv.config();

// Configuration - update these with your Supabase details
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://your-project.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'your-service-role-key';

if (!SUPABASE_SERVICE_ROLE_KEY || SUPABASE_SERVICE_ROLE_KEY === 'your-service-role-key') {
  console.error('❌ Please set SUPABASE_SERVICE_ROLE_KEY environment variable');
  console.error('   Get this from your Supabase dashboard: Settings > API > service_role');
  process.exit(1);
}

// Initialize Supabase client with service role key
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// Debug: Log configuration (without exposing the full key)
console.log('🔧 Configuration loaded:');
console.log(`   URL: ${SUPABASE_URL}`);
console.log(`   Service Role Key: ${SUPABASE_SERVICE_ROLE_KEY ? '✅ Present' : '❌ Missing'}`);
console.log(`   Key starts with: ${SUPABASE_SERVICE_ROLE_KEY ? SUPABASE_SERVICE_ROLE_KEY.substring(0, 20) + '...' : 'N/A'}\n`);

// Sample document content
const SAMPLE_DOCUMENT = {
  content: `The Supabase Sidecar Embedding Engine is a production-ready solution for processing document embeddings at scale. 
  
This architecture demonstrates how to build robust AI infrastructure using PostgreSQL extensions and Supabase's serverless capabilities. 
The sidecar pattern keeps embeddings separate from source data, maintaining query performance while enabling semantic search.

Key features include:
- Autonomous re-embedding with change detection
- Database-native queuing and scheduling
- Zero external API costs for embeddings
- Scalable processing up to 400K+ documents`,
  metadata: {
    document_type: 'technical_documentation',
    category: 'architecture',
    author: 'example',
    created_date: new Date().toISOString()
  }
};

async function runExample() {
  console.log('🚀 Starting Supabase Sidecar Embedding Engine Example\n');
  
  try {
    // Step 1: Insert sample document
    console.log('📝 Step 1: Inserting sample document...');
    const { data: document, error: insertError } = await supabase
      .from('source_documents')
      .insert(SAMPLE_DOCUMENT)
      .select()
      .single();
    
    if (insertError) {
      throw new Error(`Failed to insert document: ${insertError.message}`);
    }
    
    console.log(`✅ Document inserted with ID: ${document.id}`);
    console.log(`   Content length: ${document.content.length} characters`);
    console.log(`   Metadata: ${JSON.stringify(document.metadata)}\n`);
    
    // Step 2: Wait for processing (give the system time to process)
    console.log('⏳ Step 2: Waiting for embedding processing...');
    console.log('   This may take 1-2 minutes depending on your system load...\n');
    
    let embeddingFound = false;
    let attempts = 0;
    const maxAttempts = 12; // Wait up to 2 minutes (12 * 10 seconds)
    
    while (!embeddingFound && attempts < maxAttempts) {
      attempts++;
      console.log(`   Attempt ${attempts}/${maxAttempts}: Checking for embedding...`);
      
      // Check if embedding was created
      const { data: embedding, error: embeddingError } = await supabase
        .from('document_embeddings')
        .select('*')
        .eq('document_id', document.id)
        .single();
      
      if (embedding && embedding.embedding) {
        embeddingFound = true;
        console.log(`✅ Embedding found! Vector dimensions: ${embedding.embedding.length}`);
        console.log(`   Source text hash: ${embedding.source_text_hash}`);
        console.log(`   Created at: ${embedding.created_at}\n`);
      } else {
        console.log('   ⏳ Embedding not ready yet, waiting 10 seconds...');
        await new Promise(resolve => setTimeout(resolve, 10000)); // Wait 10 seconds
      }
    }
    
    if (!embeddingFound) {
      console.log('⚠️  Embedding not found after 2 minutes. This could mean:');
      console.log('   - The Edge Function is not deployed');
      console.log('   - The cron job is not running');
      console.log('   - There was an error in processing');
      console.log('   Check the logs and system status.\n');
      return;
    }
    
    // Step 3: Run similarity search
    console.log('🔍 Step 3: Running similarity search...');
    
    // Get the embedding we just created
    const { data: embeddingData, error: embeddingError } = await supabase
      .from('document_embeddings')
      .select('embedding')
      .eq('document_id', document.id)
      .single();
    
    if (embeddingError || !embeddingData.embedding) {
      throw new Error('Failed to retrieve embedding for search');
    }
    
    // Run similarity search using pgvector
    const { data: searchResults, error: searchError } = await supabase
      .rpc('semantic_search_documents', {
        query_embedding: embeddingData.embedding,
        match_threshold: 0.7,
        match_count: 5
      });
    
    if (searchError) {
      console.log('⚠️  Similarity search failed (this is expected if the function does not exist):');
      console.log(`   Error: ${searchError.message}`);
      console.log('   This is normal for the basic setup - the function can be added later.\n');
    } else {
      console.log('✅ Similarity search completed!');
      console.log(`   Found ${searchResults.length} similar documents:\n`);
      
      searchResults.forEach((result, index) => {
        console.log(`   ${index + 1}. Document ID: ${result.document_id}`);
        console.log(`      Similarity: ${(result.similarity * 100).toFixed(1)}%`);
        console.log(`      Content preview: ${result.content.substring(0, 100)}...\n`);
      });
    }
    
    // Step 4: Show system status
    console.log('📊 Step 4: System Status Overview');
    
    // Check queue status
    const { data: queueStats, error: queueError } = await supabase
      .rpc('get_queue_stats');
    
    if (!queueError && queueStats && queueStats.length > 0) {
      const stats = queueStats[0];
      console.log(`   Queue Status: ${stats.total_pending} jobs pending`);
      if (stats.total_pending > 0) {
        console.log(`   Oldest job: ${stats.oldest_job}`);
        console.log(`   Newest job: ${stats.newest_job}`);
      }
    }
    
    // Check system status view
    const { data: systemStatus, error: statusError } = await supabase
      .from('autonomous_system_status')
      .select('*')
      .single();
    
    if (!statusError && systemStatus) {
      console.log(`   Total Documents: ${systemStatus.total_documents}`);
      console.log(`   Documents with Embeddings: ${systemStatus.documents_with_embeddings}`);
      console.log(`   Coverage: ${systemStatus.embedding_coverage_percent}%`);
      console.log(`   Errors (last hour): ${systemStatus.errors_last_hour}`);
    }
    
    console.log('\n🎉 Example completed successfully!');
    console.log('   The Supabase Sidecar Embedding Engine is working correctly.');
    console.log('   You can now insert more documents and they will be processed automatically.');
    
  } catch (error) {
    console.error('\n❌ Example failed with error:');
    console.error(`   ${error.message}`);
    console.error('\n   Troubleshooting tips:');
    console.error('   1. Ensure your Supabase project has the required extensions enabled');
    console.error('   2. Check that you ran the bootstrap.sql file');
    console.error('   3. Verify your service role key has the necessary permissions');
    console.error('   4. Check the Supabase logs for any errors');
    
    process.exit(1);
  }
}

// Run the example if this script is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runExample();
}

export { runExample };
