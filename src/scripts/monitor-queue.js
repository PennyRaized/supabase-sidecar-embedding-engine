#!/usr/bin/env node

/**
 * Queue Monitor - Real-time monitoring of the embedding queue
 * 
 * This script monitors the embedding queue status and provides
 * real-time insights into processing performance.
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
 * Monitor queue status with real-time updates
 */
async function monitorQueue() {
  console.log('🔍 Starting queue monitor...\n');
  
  try {
    // Check documents status
    const { data: docs, error: docsError } = await supabase
      .from('source_documents')
      .select('id, status')
      .limit(1000);
    
    if (docsError) {
      console.error('❌ Error fetching documents:', docsError.message);
      return;
    }

    // Check embeddings status  
    const { data: embeddings, error: embError } = await supabase
      .from('document_embeddings')
      .select('id, created_at')
      .limit(1000);
    
    if (embError) {
      console.error('❌ Error fetching embeddings:', embError.message);
      return;
    }

    // Display status
    const totalDocs = docs?.length || 0;
    const totalEmbeddings = embeddings?.length || 0;
    const completionRate = totalDocs > 0 ? (totalEmbeddings / totalDocs * 100).toFixed(1) : 0;
    
    console.log(`📊 Queue Status:`);
    console.log(`   Documents: ${totalDocs}`);
    console.log(`   Embeddings: ${totalEmbeddings}`);
    console.log(`   Completion: ${completionRate}%`);
    console.log(`   Pending: ${Math.max(0, totalDocs - totalEmbeddings)}\n`);
    
    if (totalDocs === 0) {
      console.log('💡 No documents found. Run "npm run seed" to add sample data.');
    }
    
  } catch (error) {
    console.error('❌ Monitor error:', error.message);
  }
}

// Run monitor
monitorQueue();



