
/**
 * Seed Sample Data Script
 * 
 * Creates sample documents for testing the autonomous embedding system.
 * This script demonstrates the system's ability to handle various document types
 * and triggers the embedding generation pipeline.
 */

import { createClient } from '@supabase/supabase-js';
import { config } from 'dotenv';

// Load environment variables
config();

// Supabase client setup
const supabase = createClient(
  process.env.SUPABASE_URL || '',
  process.env.SUPABASE_ANON_KEY || ''
);

// Sample document content for testing
const SAMPLE_DOCUMENTS = [
  {
    id: '3e7c5cfe-5b14-427d-bb38-0d2f8fefabf7',
    content: `Artificial Intelligence and Machine Learning in Modern Software Development

The integration of AI and ML technologies into software development workflows has revolutionized how we build, test, and deploy applications. Modern development teams are leveraging these technologies to automate repetitive tasks, improve code quality, and enhance user experiences.

Key applications include automated code review, intelligent testing strategies, and predictive analytics for system performance. The embedding-based search systems enable developers to quickly find relevant code snippets, documentation, and solutions to complex problems.

This transformation represents a fundamental shift in how we approach software engineering, moving from purely manual processes to intelligent, automated workflows that amplify human capabilities.`
  },
  {
    id: 'dbf3df8b-064b-4742-a130-4d133c5acd73',
    content: `Q3 2024 Market Analysis: Technology Sector Growth

The technology sector continues to show robust growth across multiple verticals. Key trends include increased adoption of cloud-native architectures, expansion of AI-driven automation, and growing investment in cybersecurity solutions.

Market indicators suggest that companies investing in modern database technologies and serverless architectures are experiencing 40% faster development cycles compared to traditional infrastructure approaches. The shift toward zero-cost scaling solutions has become particularly important for startups and growing businesses.

Notable growth areas include: edge computing platforms, AI-powered development tools, and autonomous system architectures. These trends indicate a continued evolution toward more efficient, cost-effective technology solutions.`
  },
  {
    id: '2774e521-26cd-48f9-997c-566e051ddfa0',
    content: `Database Optimization Strategies for High-Volume Applications

Effective database optimization requires a multi-layered approach encompassing schema design, query optimization, and infrastructure scaling. For applications processing large volumes of data, traditional optimization techniques must be augmented with modern architectural patterns.

Key strategies include implementing sidecar architectures for heavy computational tasks, utilizing vector databases for similarity search, and leveraging PostgreSQL extensions for specialized workloads. The combination of pgvector for embeddings, pg_cron for scheduling, and pg_net for HTTP requests creates powerful automation capabilities.

Performance optimization should focus on: minimizing query complexity, optimizing index usage, implementing efficient caching strategies, and designing for horizontal scalability. These principles ensure applications can handle growth without proportional increases in infrastructure costs.`
  },
  {
    id: 'f1e8d9c2-3b4a-5c6d-7e8f-9a0b1c2d3e4f',
    content: `Zero-Cost Embedding Engine: Autonomous Document Processing

A revolutionary approach to document embedding generation that eliminates infrastructure costs while maintaining enterprise-grade performance and reliability. This system processes thousands of documents autonomously using sophisticated database-driven orchestration.

Features include automatic content change detection, self-healing error recovery, and infinite scalability without additional server costs. The system is designed for modern applications requiring intelligent document search, similarity matching, and content recommendations.

Perfect for startups, growing businesses, and any organization seeking to implement AI-powered search capabilities without the complexity and expense of traditional infrastructure. The solution integrates seamlessly with existing Supabase applications and requires minimal configuration.`
  },
  {
    id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    content: `Edge Function Implementation Guide

Edge Functions provide serverless execution environments optimized for low latency and high throughput. The Supabase Edge Function runtime supports TypeScript and includes built-in AI capabilities for embedding generation.

Key implementation patterns include:

1. Self-invoking functions for autonomous processing
2. Micro-batching for optimal resource utilization  
3. Built-in error handling and retry mechanisms
4. Integration with PostgreSQL for state management

The gte-small model provides 384-dimensional embeddings optimized for English text up to 512 tokens. For larger documents, implement chunking strategies that preserve semantic context across boundaries.

Best practices include environment-based configuration, structured error logging, and comprehensive monitoring of processing metrics. These patterns ensure production-ready deployments that scale efficiently.`
  },
  {
    id: '12345678-90ab-cdef-1234-567890abcdef',
    content: `Scalable Vector Similarity Search in Production Systems

This research examines the performance characteristics of vector similarity search systems under high-volume production workloads. We analyze the trade-offs between embedding dimensionality, search accuracy, and computational efficiency across various real-world scenarios.

Our findings indicate that 384-dimensional embeddings provide optimal balance for general-purpose applications, achieving 85% of the accuracy of larger models while requiring 75% less storage and processing time. The study includes comprehensive benchmarks across 100,000+ documents with statistical validation.

Key contributions include: methodology for embedding model selection, optimization strategies for high-volume processing, and architectural patterns for cost-effective scaling. These results provide practical guidance for implementing production vector search systems.`
  },
  {
    id: 'fedcba09-8765-4321-fedc-ba0987654321',
    content: `Building Autonomous Systems with Database Orchestration

Modern applications increasingly require autonomous operation capabilities that minimize manual intervention while maintaining reliability and performance. Database-driven orchestration provides a powerful pattern for achieving these goals.

This tutorial covers implementing self-healing systems using PostgreSQL's advanced features including cron scheduling, HTTP requests, and message queuing. The combination creates sophisticated workflows that operate independently while providing comprehensive observability.

Step-by-step implementation includes: setting up automated triggers, configuring self-invoking processes, implementing error recovery mechanisms, and monitoring system health. The resulting architecture provides enterprise-grade automation without the complexity of external orchestration systems.`
  },
  {
    id: '11111111-2222-3333-4444-555555555555',
    content: `Case Study: 100K Document Embedding Processing

This case study details the implementation and performance validation of an autonomous embedding system processing over 100,000 documents. The system demonstrates zero-cost scaling using database-driven orchestration and serverless compute.

Challenge: Process large document corpus without infrastructure investment
Solution: Self-invoking Edge Functions with PostgreSQL orchestration
Results: 14.2 hours total processing time, 99.97% success rate, $0 infrastructure cost

Key learnings include the importance of micro-batching for reliability, hash-based change detection for efficiency, and sidecar architecture for performance optimization. The system processed an average of 117 documents per minute while maintaining consistent memory usage.

This architecture provides a replicable pattern for organizations requiring high-volume document processing without traditional infrastructure investments.`
  }
];

/**
 * Insert sample documents into the database
 */
async function seedDocuments() {
  console.log('🌱 Starting to seed sample documents...');
  
  try {
    // Check if documents already exist
    const { data: existing, error: checkError } = await supabase
      .from('source_documents')
      .select('id')
      .in('id', SAMPLE_DOCUMENTS.map(doc => doc.id));

    if (checkError) {
      throw new Error(`Failed to check existing documents: ${checkError.message}`);
    }

    const existingIds = new Set(existing?.map(doc => doc.id) || []);
    const newDocuments = SAMPLE_DOCUMENTS.filter(doc => !existingIds.has(doc.id));

    if (newDocuments.length === 0) {
      console.log('✅ All sample documents already exist');
      return;
    }

    // Insert new documents
    const { data, error } = await supabase
      .from('source_documents')
      .insert(newDocuments)
      .select();

    if (error) {
      throw new Error(`Failed to insert documents: ${error.message}`);
    }

    console.log(`✅ Successfully inserted ${newDocuments.length} new documents`);
    console.log('📄 Inserted documents:');
    newDocuments.forEach(doc => {
      console.log(`   - ${doc.id}`);
    });

    // Give a moment for triggers to process
    console.log('\n⏳ Waiting for embedding pipeline to process documents...');
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Check if embeddings are being generated
    const { data: embeddings, error: embError } = await supabase
      .from('document_embeddings')
      .select('document_id')
      .in('document_id', newDocuments.map(doc => doc.id));

    if (embError) {
      console.warn(`⚠️ Could not check embedding status: ${embError.message}`);
    } else {
      const embeddedCount = embeddings?.length || 0;
      console.log(`🔄 Embeddings generated: ${embeddedCount}/${newDocuments.length}`);
      
      if (embeddedCount < newDocuments.length) {
        console.log('⏱️ Note: Embedding generation is asynchronous and may take a few minutes');
        console.log('   You can monitor progress with: SELECT COUNT(*) FROM document_embeddings;');
      }
    }

  } catch (error) {
    console.error('❌ Error seeding documents:', error.message);
    process.exit(1);
  }
}

/**
 * Display system status and helpful information
 */
async function displaySystemStatus() {
  console.log('\n📊 System Status Check:');
  
  try {
    // Check total documents
    const { count: totalDocs, error: docsError } = await supabase
      .from('source_documents')
      .select('*', { count: 'exact', head: true });

    if (docsError) throw docsError;

    // Check total embeddings
    const { count: totalEmbeddings, error: embeddingsError } = await supabase
      .from('document_embeddings')
      .select('*', { count: 'exact', head: true });

    if (embeddingsError) throw embeddingsError;

    console.log(`   📄 Total Documents: ${totalDocs || 0}`);
    console.log(`   🔮 Total Embeddings: ${totalEmbeddings || 0}`);
    console.log(`   📈 Processing Rate: ${totalEmbeddings || 0}/${totalDocs || 0} (${Math.round(((totalEmbeddings || 0) / (totalDocs || 1)) * 100)}%)`);

    // Check recent processing activity
    const { data: recentEmbeddings, error: recentError } = await supabase
      .from('document_embeddings')
      .select('created_at')
      .order('created_at', { ascending: false })
      .limit(1);

    if (!recentError && recentEmbeddings?.length > 0) {
      const lastProcessed = new Date(recentEmbeddings[0].created_at);
      const timeSince = Math.round((Date.now() - lastProcessed.getTime()) / 1000);
      console.log(`   ⏰ Last Processing: ${timeSince} seconds ago`);
    }

  } catch (error) {
    console.warn(`⚠️ Could not fetch system status: ${error.message}`);
  }
}

/**
 * Main execution function
 */
async function main() {
  console.log('🚀 Supabase Embedding Engine - Sample Data Seeder\n');

  // Validate environment
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
    console.error('❌ Missing required environment variables:');
    console.error('   SUPABASE_URL and SUPABASE_ANON_KEY must be set');
    console.error('   Copy .env.example to .env and configure your Supabase credentials');
    process.exit(1);
  }

  // Test connection
  try {
    const { data, error } = await supabase
      .from('source_documents')
      .select('id')
      .limit(1);

    if (error) {
      throw new Error(`Database connection failed: ${error.message}`);
    }

    console.log('✅ Connected to Supabase successfully\n');
  } catch (error) {
    console.error('❌ Failed to connect to Supabase:', error.message);
    console.error('   Please check your SUPABASE_URL and SUPABASE_ANON_KEY');
    process.exit(1);
  }

  // Seed documents
  await seedDocuments();

  // Display status
  await displaySystemStatus();

  console.log('\n🎯 Next Steps:');
  console.log('   1. Monitor embedding generation: SELECT * FROM document_embeddings;');
  console.log('   2. Test similarity search: Use the embedding vectors for document similarity');
  console.log('   3. Check autopilot function: Update a document to trigger re-embedding');
  console.log('\n✨ Sample data seeding complete!');
}

// Execute if run directly
if (import.meta.main) {
  main().catch(error => {
    console.error('💥 Unexpected error:', error);
    process.exit(1);
  });
}

export { seedDocuments, displaySystemStatus, SAMPLE_DOCUMENTS };



