#!/usr/bin/env node

/**
 * Cost Analysis - Calculate the cost savings of the zero-cost architecture
 * 
 * Compares our Supabase-based solution against traditional 
 * cloud infrastructure costs for embedding processing.
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
 * Traditional infrastructure cost estimates
 */
const TRADITIONAL_COSTS = {
  redis: 50,        // Redis Cloud for queue
  workers: 200,     // 2 worker instances
  monitoring: 30,   // Application monitoring
  orchestration: 50, // Container orchestration
  api: 100,         // External embedding API calls
  maintenance: 70   // DevOps and maintenance
};

/**
 * Calculate cost analysis
 */
async function analyzeCosts() {
  console.log('💰 Supabase Zero-Cost Architecture - Cost Analysis\n');
  
  try {
    // Get system statistics
    const { data: docs, error: docsError } = await supabase
      .from('source_documents')
      .select('id, created_at')
      .limit(1000);
    
    if (docsError) {
      console.error('❌ Error fetching documents:', docsError.message);
      return;
    }

    const { data: embeddings, error: embError } = await supabase
      .from('document_embeddings')
      .select('id, created_at')
      .limit(1000);
    
    if (embError) {
      console.error('❌ Error fetching embeddings:', embError.message);
      return;
    }

    const totalDocs = docs?.length || 0;
    const totalEmbeddings = embeddings?.length || 0;
    
    // Calculate traditional costs
    const monthlyTraditional = Object.values(TRADITIONAL_COSTS).reduce((sum, cost) => sum + cost, 0);
    const yearlyTraditional = monthlyTraditional * 12;
    
    // Our costs (Supabase free tier)
    const ourMonthlyCost = 0;
    const ourYearlyCost = 0;
    
    // Cost per document
    const costPerDoc = totalDocs > 0 ? monthlyTraditional / totalDocs : 0;
    
    console.log('📊 Cost Comparison:');
    console.log('');
    console.log('Traditional Infrastructure:');
    console.log(`   Redis Queue:        $${TRADITIONAL_COSTS.redis}/month`);
    console.log(`   Worker Instances:   $${TRADITIONAL_COSTS.workers}/month`);
    console.log(`   Monitoring:         $${TRADITIONAL_COSTS.monitoring}/month`);
    console.log(`   Orchestration:      $${TRADITIONAL_COSTS.orchestration}/month`);
    console.log(`   API Calls:          $${TRADITIONAL_COSTS.api}/month`);
    console.log(`   Maintenance:        $${TRADITIONAL_COSTS.maintenance}/month`);
    console.log(`   ─────────────────────────────────`);
    console.log(`   Monthly Total:      $${monthlyTraditional}/month`);
    console.log(`   Yearly Total:       $${yearlyTraditional}/year`);
    console.log('');
    
    console.log('Our Supabase Solution:');
    console.log(`   Database:           $0/month (free tier)`);
    console.log(`   Edge Functions:     $0/month (free tier)`);
    console.log(`   Embeddings:         $0/month (built-in AI)`);
    console.log(`   Queue (pgmq):       $0/month (PostgreSQL extension)`);
    console.log(`   Monitoring:         $0/month (built-in logs)`);
    console.log(`   Maintenance:        $0/month (autonomous operation)`);
    console.log(`   ─────────────────────────────────`);
    console.log(`   Monthly Total:      $${ourMonthlyCost}/month`);
    console.log(`   Yearly Total:       $${ourYearlyCost}/year`);
    console.log('');
    
    // Savings calculation
    const monthlySavings = monthlyTraditional - ourMonthlyCost;
    const yearlySavings = yearlyTraditional - ourYearlyCost;
    
    console.log('💡 Cost Savings:');
    console.log(`   Monthly Savings:    $${monthlySavings}`);
    console.log(`   Yearly Savings:     $${yearlySavings}`);
    console.log(`   ROI:                ∞% (zero cost vs. ${monthlyTraditional}/month)`);
    console.log('');
    
    // Processing statistics
    console.log('📈 Processing Statistics:');
    console.log(`   Documents Processed: ${totalDocs}`);
    console.log(`   Embeddings Generated: ${totalEmbeddings}`);
    console.log(`   Traditional Cost/Doc: $${costPerDoc.toFixed(4)}`);
    console.log(`   Our Cost/Doc: $0.00`);
    console.log('');
    
    console.log('🎯 Key Advantages:');
    console.log('   ✅ Zero infrastructure costs');
    console.log('   ✅ No maintenance overhead');
    console.log('   ✅ Automatic scaling');
    console.log('   ✅ Built-in monitoring');
    console.log('   ✅ Production-ready reliability');
    
  } catch (error) {
    console.error('❌ Cost analysis error:', error.message);
  }
}

// Run analysis
analyzeCosts();



