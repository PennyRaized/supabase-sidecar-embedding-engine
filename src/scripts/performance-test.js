#!/usr/bin/env node

/**
 * Performance Test - Benchmark the embedding system
 * 
 * Tests the embedding system performance with sample data
 * and measures processing times and success rates.
 */

import { createClient } from '@supabase/supabase-js';
import { config } from 'dotenv';

// Load environment variables
config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('❌ Missing required environment variables: SUPABASE_URL, SUPABASE_ANON_KEY');
  console.error('   Please copy .env.example to .env and configure your Supabase credentials');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseAnonKey);

/**
 * Generate test documents for performance testing
 */
function generateTestDocuments(count = 10) {
  const documents = [];
  const topics = ['AI research', 'Machine learning', 'Database optimization', 'Cloud architecture', 'Software engineering'];
  
  for (let i = 0; i < count; i++) {
    const topic = topics[i % topics.length];
    documents.push({
      title: `Performance Test Document ${i + 1}`,
      content: `This is a test document about ${topic}. `.repeat(50), // ~500 chars
      source_url: `https://example.com/test-${i + 1}`,
      metadata: { 
        test: true, 
        batch: Math.floor(Date.now() / 1000),
        topic: topic
      }
    });
  }
  
  return documents;
}

/**
 * Run performance test
 */
async function runPerformanceTest() {
  console.log('🚀 Starting performance test...\n');
  
  const testSize = 5;
  const startTime = Date.now();
  
  try {
    // Generate test documents
    console.log(`📝 Generating ${testSize} test documents...`);
    const testDocs = generateTestDocuments(testSize);
    
    // Insert test documents
    console.log('💾 Inserting documents...');
    const { data: insertedDocs, error: insertError } = await supabase
      .from('source_documents')
      .insert(testDocs)
      .select('id');
    
    if (insertError) {
      console.error('❌ Insert error:', insertError.message);
      return;
    }
    
    const insertTime = Date.now() - startTime;
    console.log(`✅ Inserted ${insertedDocs.length} documents in ${insertTime}ms\n`);
    
    // Monitor embedding generation
    console.log('⏱️  Monitoring embedding generation...');
    let embedded = 0;
    let attempts = 0;
    const maxAttempts = 60; // 5 minutes max
    
    while (embedded < testSize && attempts < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 5000)); // Wait 5s
      
      const { data: embeddings, error: embError } = await supabase
        .from('document_embeddings')
        .select('document_id')
        .in('document_id', insertedDocs.map(d => d.id));
      
      if (embError) {
        console.error('❌ Embedding check error:', embError.message);
        break;
      }
      
      embedded = embeddings?.length || 0;
      attempts++;
      
      const elapsed = Math.round((Date.now() - startTime) / 1000);
      process.stdout.write(`\r   Progress: ${embedded}/${testSize} (${elapsed}s)`);
    }
    
    console.log('\n');
    
    // Final results
    const totalTime = Date.now() - startTime;
    const completionRate = (embedded / testSize * 100).toFixed(1);
    
    console.log('📊 Performance Results:');
    console.log(`   Documents: ${testSize}`);
    console.log(`   Embedded: ${embedded}`);
    console.log(`   Success Rate: ${completionRate}%`);
    console.log(`   Total Time: ${Math.round(totalTime / 1000)}s`);
    console.log(`   Rate: ${(embedded / (totalTime / 60000)).toFixed(1)} docs/minute`);
    
    if (embedded === testSize) {
      console.log('\n✅ Performance test completed successfully!');
    } else {
      console.log('\n⚠️  Some embeddings may still be processing...');
    }
    
  } catch (error) {
    console.error('❌ Performance test error:', error.message);
  }
}

// Run test
runPerformanceTest();



