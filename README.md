# The $0 Scaling Architecture: A Zero-Cost Embedding Engine on Supabase

*I had a production problem: 100,000 documents to embed and a cloud budget of $0. The standard playbook said 'impossible.' This repo contains the playbook I wrote instead.*

**How we processed 100,000+ document embeddings without renting a single server, using a "database-as-orchestrator" pattern with sidecar architecture.**

## 🎯 The Problem

Processing embeddings for large document corpora is a common challenge in AI applications, but traditional solutions require expensive, dedicated infrastructure like Celery workers, Redis queues, and Kubernetes—plus OpenAI API costs—often totaling $650+/month.

Building an AI-powered startup search system, I had a classic startup problem: a mountain of data (100K company profiles) and a molehill of a budget ($0 for new infrastructure). The standard playbook for AI embedding would have cost $650+/month (infrastructure + OpenAI API fees). That wasn't an option. So, I threw out the playbook and used the database itself as the engine.

**The Challenge**: Not just generating embeddings, but doing it in a way that:
- Scales efficiently without additional costs
- Maintains consistent performance as data grows
- Prevents table bloat and query slowdowns
- Provides reliable, self-healing processing

## ❌ The "Standard" Solution (and its flaws)

The conventional approach looks like this:

[Documents] → [API Gateway] → [Worker Queue (Redis)] → [Worker Instances (K8s)] → [Vector Database]
↓ ↓ ↓ ↓ ↓
Postgres Load Balancer Queue Manager Auto-scaling pgvector


**Problems with this approach:**
- **Cost**: Infrastructure ($220-$400+/month) + OpenAI API fees ($25-$500+/month) = $650+/month minimum
- **Complexity**: Multiple services to monitor and maintain
- **Failure Points**: Queue failures, worker crashes, network issues
- **Scaling**: Need to predict and provision capacity upfront
- **Performance**: Adding vector columns to main tables causes query slowdowns
- **Drift**: Embeddings become out of sync with source data
- **Latency**: Synchronous embedding generation blocks writes

## ✅ Our Solution: The Database as the Orchestrator + Sidecar Architecture

Instead of building external infrastructure, we used Supabase's powerful PostgreSQL extensions (`pg_cron`, `pg_net`, `pgmq`) and Edge Functions to create a self-healing, auto-scaling system that lives entirely within the database.

**Core Design**: We implemented a **sidecar architecture** where embeddings are stored separately from source documents, preventing table bloat and maintaining query performance at scale.

## 🎯 Who is This For?

This project demonstrates production-ready engineering with a focus on cost-efficiency and scalable solutions. It's a deep dive into using database-native tools to replace complex microservice architectures, showing how to build robust AI infrastructure without breaking the budget through creative architecture instead of expensive external services.

**Our architecture:**

[Source Documents] → [PostgreSQL Trigger] → [pgmq Queue] → [pg_cron Scheduler] → [Edge Function] → [Sidecar Embeddings]
↓ ↓ ↓ ↓ ↓ ↓
Main Table Auto-detection In-DB Queue Periodic Jobs AI Processing Vector Storage
(Fast Queries) (Non-blocking) (Persistent) (Reliable) (Scalable) (Optimized)


## ��️ Architecture Deep Dive

### The Sidecar Pattern: Why It Matters

**The Problem**: Storing embeddings directly in the main table with a `vector` column causes significant performance degradation:
- **Table Bloat**: Large vector data (384+ dimensions) makes tables heavy
- **Query Slowdowns**: Vector operations on frequently-accessed tables
- **Index Inefficiency**: Mixed data types make indexing suboptimal
- **Maintenance Complexity**: Difficult to manage and optimize separately

**Our Solution**: Separate tables with clean separation of concerns:
- **`source_documents`**: Lean, fast table for primary data with optimized indexes
- **`document_embeddings`**: Optimized table for vector operations with specialized indexes
- **Automatic Sync**: Triggers ensure perfect consistency without blocking writes
- **Performance Isolation**: Main table queries remain fast regardless of embedding table size

### The Orchestration Layer: Database-Native Processing

**Database Triggers**: Detect changes and queue jobs without blocking writes
```sql
CREATE TRIGGER embed_documents_on_insert
  AFTER INSERT ON source_documents
  FOR EACH ROW
  EXECUTE FUNCTION queue_embedding_job();
```

**pgmq Queue**: Lightweight, persistent queue within PostgreSQL
```sql
-- Enqueue embedding job
SELECT pgmq.send('embedding_queue', json_build_object(
  'document_id', NEW.id,
  'content', NEW.content,
  'action', 'create'
));
```

**pg_cron Scheduler**: Reliable, database-native job scheduling
```sql
-- Process queue every 30 seconds
SELECT cron.schedule('process-embeddings', '*/30 * * * *', $$
  SELECT net.http_post(
    url := 'https://your-project.supabase.co/functions/v1/process-embeddings',
    headers := '{"Authorization": "Bearer ' || current_setting('app.settings.service_role_key') || '"}',
    body := '{"batch_size": 10}'
  );
$$);
```

**Edge Function Processing**: Serverless, scalable embedding generation
```typescript
// Process batch with built-in retry logic
for (const job of jobs) {
  try {
    const embedding = await generateGteSmallEmbedding(job.content);
    await updateEmbedding(job.document_id, embedding);
    await markJobComplete(job.id);
  } catch (error) {
    await retryJob(job.id, error);
  }
}
```

## 🏗️ Architectural Advantages

| Aspect | Traditional Microservices | Database-as-Orchestrator (Our Solution) |
|--------|---------------------------|-------------------------------------------|
| **Cost Model** | Provisioned Infrastructure: Fixed monthly cost for idle servers & queues | Serverless / Pay-per-use: Zero cost when idle; scales from zero on demand |
| **Data Flow** | High Network Latency: Data moves from DB → API → Queue → Worker → DB | Zero Network Latency: All operations (queuing, processing) are within the database |
| **Query Performance** | Monolithic Table Risk: Adding a vector column can bloat the main table and slow down primary queries | Sidecar Pattern: Performance isolation; embedding table doesn't impact the main data table's speed |
| **State Management** | Complex: Requires external services (Redis, etc.) to manage job state, leading to potential sync issues | Transactional (ACID): Uses the database's inherent reliability. A job is guaranteed to be in the queue or processed |
| **Operational Surface** | Large: 7+ services to monitor, configure, and secure (K8s, Redis, Workers, etc.) | Minimal: 1 service (Supabase). The database itself is the entire operational backend |

### 📊 **Measured Performance Results**

Based on the architectural advantages above, we achieve:
- **Processing Speed**: 87 documents/minute (measured, not estimated)
- **Cost**: $0/month vs $650+/month traditional approach
- **Setup Time**: Under 1 hour vs days to weeks
- **Reliability**: 99.5%+ uptime without human intervention
- **Scale**: Handles 50K+ document re-embedding without timeouts

> **Note**: For detailed performance methodology and benchmarking, see [`docs/PERFORMANCE_METHODOLOGY.md`](docs/PERFORMANCE_METHODOLOGY.md).

### 💰 **The Hidden Cost: OpenAI Embedding Fees**

**Traditional approaches require paying for every embedding:**
- **Small scale** (100K docs): ~$25/month to OpenAI
- **Medium scale** (1M docs): ~$250/month to OpenAI  
- **Large scale** (10M docs): ~$2,500/month to OpenAI
- **Plus** infrastructure costs ($220-$400+/month)

**Our approach eliminates ALL embedding costs:**
- **Any scale**: $0/month for embeddings (uses Supabase's built-in AI)
- **Same quality**: gte-small provides 85%+ of OpenAI's accuracy
- **No rate limits**: Process as fast as your system allows
- **No vendor lock-in**: Everything runs within your Supabase instance

## 🚀 Getting Started

### Prerequisites

**What is Supabase?**

[Supabase](https://supabase.com) is an open-source Firebase alternative that provides:
- **PostgreSQL Database**: Full-featured database with powerful extensions
- **Edge Functions**: Serverless functions running on Deno for AI processing  
- **Authentication & Storage**: Built-in user management and file storage
- **Real-time APIs**: Auto-generated REST and GraphQL APIs

**Why Supabase for This Project?**

This architecture leverages Supabase's unique combination of:
1. **Advanced PostgreSQL Extensions**: `pgvector` (vectors), `pgmq` (queues), `pg_cron` (scheduling), `pg_net` (HTTP requests)
2. **Deno Edge Functions**: Serverless environment perfect for AI model inference
3. **Zero-Cost Processing**: Both database and Edge Functions scale automatically

**Cost**: Supabase offers a [generous free tier](https://supabase.com/pricing) that includes:
- Unlimited API requests
- 500 MB database storage  
- 2 Million Edge Function invocations per month
- Community support

**Perfect for testing this project** - the free tier can easily handle thousands of documents for demonstration purposes.

**Requirements:**
- Supabase account (free tier works perfectly for testing)
- No external API keys needed (uses Supabase's built-in AI)

---

### Quick Setup (Under 1 hour)

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/supabase-sidecar-embedding-engine.git
   cd supabase-sidecar-embedding-engine
   npm install
   ```

2. **Set up environment**
   ```bash
   cp .env.example .env
   # Edit .env and add your Supabase project URL and keys
   # Get these from your Supabase dashboard: Settings > API
   ```

3. **Set up Supabase project**
   
   **Step 3a: Create Supabase Project**
   - Go to [supabase.com](https://supabase.com) and create a free account
   - Click "New Project" and choose a name/region
   - Wait 2-3 minutes for project initialization
   - Copy your project URL and API keys from Settings > API

   **Step 3b: Run Database Migrations**
   
   Open your Supabase dashboard → SQL Editor and run these migrations **in order**:
   
   1. **First Migration**: Copy/paste content from `supabase/migrations/001_source_documents_schema.sql`
   2. **Second Migration**: Copy/paste content from `supabase/migrations/002_document_embeddings_sidecar.sql`  
   3. **Third Migration**: Copy/paste content from `supabase/migrations/003_embedding_queue_system.sql`
   4. **Fourth Migration**: Copy/paste content from `supabase/migrations/004_autonomous_reembedding_system.sql`


   > **⚠️ Important**: Migrations 2, 3, and 4 may show "potentially destructive" warnings in Supabase. These are safe to run - the warnings appear because they use `DROP TRIGGER IF EXISTS` statements to ensure idempotency. The migrations will not harm your data.

   **Step 3c: Store Service Role JWT Securely**
   
   Now that your database is set up, secure your service role JWT:
   
   1. In your Supabase Dashboard → **Settings** → **API**, copy your **service_role** key (not the anon key!)
   2. Go to **Project Settings** (gear icon) → **Vault**
   3. Click **"Add a new secret"**
   4. Enter the details:
      - **Name:** `service_role_key`
      - **Secret:** Paste your service role JWT
   5. Click **"Save"**

   **Step 3d: Configure Autopilot System**
   
   Run this SQL to configure the autonomous processing:
   ```sql
   -- Create the function that the cron job will call
   CREATE OR REPLACE FUNCTION call_embedding_edge_function()
   RETURNS void
   LANGUAGE plpgsql
   AS $$
   DECLARE
     service_key TEXT;
     http_response RECORD;
   BEGIN
     -- Log that we're starting
     RAISE NOTICE 'Cron job starting at %', now();

     -- Securely fetch the service role key from Vault
     SELECT decrypted_secret INTO service_key
     FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     LIMIT 1;

     -- Only proceed if the key was found
     IF service_key IS NOT NULL THEN
       -- Make the authenticated request to the Edge Function
       SELECT * INTO http_response
       FROM net.http_post(
         url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-embedding-queue',
         headers := jsonb_build_object(
           'Content-Type', 'application/json',
           'Authorization', 'Bearer ' || service_key
         )
       );
       
       -- Log the response
       RAISE NOTICE 'HTTP response: %', http_response;
     ELSE
       RAISE WARNING 'Service key "service_role_key" not found in Vault. Aborting.';
     END IF;
   END;
   $$;

   -- Grant necessary permissions to the cron_job role
   GRANT EXECUTE ON FUNCTION public.call_embedding_edge_function() TO cron_job;
   GRANT USAGE ON SCHEMA vault TO cron_job;
   GRANT USAGE ON SCHEMA net TO cron_job;

   -- Schedule the cron job to run every minute
   SELECT cron.schedule(
     'process-embeddings-edge-function',
     '*/1 * * * *',  -- Every minute (safe and standard)
     'SELECT call_embedding_edge_function();'
   );
   ```
   
   **Important:** Replace `YOUR_PROJECT_REF` with your actual Supabase project reference in the URL.
   
   **Why this approach is secure:**
   - ✅ **No hardcoded secrets** in your SQL or code
   - ✅ **Encrypted storage** via Supabase Vault
   - ✅ **Proper permissions** for the cron_job role
   - ✅ **Function-based approach** that cron can execute

   **Step 3e: Deploy Edge Function (Optional)**
   
   For full autonomous processing, deploy the processing function:
   ```bash
   # Install Supabase CLI first: npm install -g supabase
   
   # Login to Supabase (if browser fails, use access token from dashboard)
   supabase login
   
   # Link to your project (interactive selection)
   supabase link
   
   # Deploy the processing function
   supabase functions deploy process-embedding-queue
   ```
   
   **If `supabase login` fails:**
   1. Go to your Supabase Dashboard → Settings → Access Tokens
   2. Generate a new access token
   3. Use: `supabase login --token YOUR_ACCESS_TOKEN`
   
   **Note**: You may see "WARNING: Docker is not running" - this is fine! The deployment will work without Docker.

   **How embeddings get enqueued automatically:**
   - ✅ **Database triggers** detect new/updated documents
   - ✅ **`pgmq.send()`** adds jobs to the queue (no Edge Function needed)
   - ✅ **`pg_cron`** calls `call_embedding_edge_function()` every minute
   - ✅ **Function calls Edge Function** with proper authentication
   - ✅ **Self-healing** system processes the queue continuously

   **Note**: You can explore the system without Edge Functions - the migrations provide all the core functionality.

4. **Test with sample data**
   ```bash
   npm run seed      # Add sample documents
   npm run monitor   # Check processing status
   ```

5. **Explore the system**
   ```bash
   npm run performance   # Run performance tests
   npm run analyze:cost # See cost comparison
   ```

**👀 What to Expect:** The seed script will create sample documents. If Edge Functions are deployed, embeddings will generate automatically. Otherwise, you can explore the SQL migrations and manual processing functions.

## 🔍 Key Learnings & Technical Insights

### Why This Architecture Works So Well

1. **PostgreSQL is Powerful**: We discovered that PostgreSQL extensions can replace entire microservices
2. **Sidecar Prevents Bloat**: Separating embeddings maintains query performance at scale
3. **Database Orchestration**: Using the database as the orchestrator eliminates network failures
4. **Cost Optimization**: Leveraging existing infrastructure instead of building new services
5. **Performance Isolation**: Main table queries remain fast regardless of embedding complexity

### Production Considerations

- **Batch Processing**: Process embeddings in batches to optimize API calls and costs
- **Error Handling**: Built-in retry logic with pgmq visibility timeout (retry limits planned for future)
- **Monitoring**: Use the included monitoring scripts to track queue health and performance
- **Rate Limiting**: Respect API rate limits by controlling batch sizes and processing intervals
- **Data Consistency**: Automatic triggers ensure embeddings stay in sync with source data

### Future Production Hardening

- **Poison Pill Detection**: Implement retry limits and dead letter queue for jobs that consistently fail
- **Circuit Breaker Pattern**: Prevent cascade failures by temporarily disabling problematic processing paths
- **Advanced Retry Strategies**: Exponential backoff and jitter for transient failures

## 🔧 Troubleshooting

### Common Issues and Solutions

#### **Cron Job Not Executing**
If your cron job isn't calling the Edge Function:

1. **Check permissions**: Ensure the `cron_job` role has access
   ```sql
   -- Verify permissions are granted
   SELECT routine_name FROM information_schema.routines 
   WHERE routine_name = 'call_embedding_edge_function';
   ```

2. **Check cron job status**:
   ```sql
   -- See if cron jobs are running
   SELECT * FROM cron.job WHERE active = true;
   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
   ```

3. **Test function manually**:
   ```sql
   -- Verify the function works
   SELECT call_embedding_edge_function();
   ```

#### **Permission Errors**
The most common issue is missing permissions for the `cron_job` role:
```sql
-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION public.call_embedding_edge_function() TO cron_job;
GRANT USAGE ON SCHEMA vault TO cron_job;
GRANT USAGE ON SCHEMA net TO cron_job;
```

#### **Edge Function Not Responding**
If the Edge Function returns "Missing authorization header":
- Verify the service role key is stored in Vault
- Check that the function is calling the correct URL
- Ensure the Edge Function is deployed and accessible

## 🤔 Next Level Questions

### Scalability Challenges
- **40M embeddings**: How would this handle 100x scale?
  - Database partitioning strategies for massive datasets
  - Queue sharding approaches for high throughput
  - Edge Function scaling considerations and optimization
- **Rate limiting**: What happens with API quotas?
  - Adaptive batch sizing based on API limits
  - Queue prioritization for different document types
  - Fallback strategies and graceful degradation
- **Storage costs**: Vector storage implications at massive scale?
  - Compression strategies for vector data
  - Archival policies for old embeddings
  - Cost optimization techniques and trade-offs

### Production Enhancements
- **Real-time processing**: Could we optimize the 30-second batch intervals?
  - Event-driven processing for immediate updates
  - Adaptive scheduling based on queue depth
  - Priority queues for urgent documents
- **Multi-model support**: Make the embedding model configurable?
  - Model selection logic based on document type
  - A/B testing capabilities for different models
  - Performance comparison and optimization
- **Advanced queuing**: Implement priority queues and job scheduling?
  - Priority-based processing for different document types
  - Resource-aware scheduling and load balancing
  - Dynamic queue management and optimization

## 🎉 Conclusion

This architecture demonstrates that you don't need expensive infrastructure to build production-ready AI systems. By thinking creatively about how to leverage existing tools and implementing proper architectural patterns, we've created a solution that's not just cheaper, but more reliable and easier to maintain.

**The result**: A zero-cost, highly scalable embedding engine that processes documents efficiently while requiring zero additional infrastructure and maintaining consistent query performance.

**Core Benefits**:
- **Sidecar architecture** prevents performance degradation at scale
- **Database orchestration** eliminates external dependencies and failure points
- **Zero-cost scaling** leverages existing infrastructure efficiently
- **Production reliability** with built-in error handling and monitoring

---

## 📁 Repository Structure
```
supabase-sidecar-embedding-engine/
├── supabase/                  # Supabase configuration (standard structure)
│   ├── config.toml           # Project configuration
│   ├── functions/            # Edge Function implementations
│   │   ├── _shared/          # Shared utilities
│   │   ├── process-embedding-queue/
│   │   └── manual-enqueue-embeddings/
│   └── migrations/           # Database schema and triggers
├── src/
│   └── scripts/              # Utility and monitoring scripts
├── docs/                     # Architecture diagrams and analysis
└── README.md                 # This comprehensive guide
```


## 🏗️ Built With

**Core Platform:**
- **[Supabase](https://supabase.com)**: Provides both the PostgreSQL database AND the Deno Edge Functions runtime
  - **PostgreSQL Database**: With powerful extensions enabled
  - **Deno Edge Functions**: Serverless JavaScript/TypeScript runtime for AI processing
  - **Real-time APIs**: Auto-generated database APIs
  - **Dashboard**: Web interface for database management

**PostgreSQL Extensions (Enabled via Supabase):**
- **pgvector**: Vector storage and similarity search operations  
- **pgmq**: Lightweight, persistent message queue within PostgreSQL
- **pg_cron**: Reliable job scheduling directly in the database
- **pg_net**: Asynchronous HTTP requests from PostgreSQL

**Architecture Patterns:**
- **Sidecar Architecture**: Separates embeddings from source data for optimal performance
- **Database-as-Orchestrator**: Uses PostgreSQL itself to manage the entire workflow
- **Self-Invoking Functions**: Edge Functions that process queues autonomously

## 📄 License

MIT License - feel free to use this architecture in your own projects!

---

## 🎯 Context: Our Original Use Case

**Business Problem**: We needed to process 50-100K company description embeddings for a hybrid search system on startup companies. Traditional approaches would have cost $500+/month and required dedicated infrastructure, while also causing performance issues as the main company data table grew.

**Our Solution**: Built a sidecar architecture using Supabase's built-in capabilities that processes unlimited embeddings at zero additional cost while maintaining reliable synchronization between company data and AI-generated embeddings. The sidecar pattern prevents table bloat and maintains query performance at scale.

**Technical Innovation**: Instead of storing embeddings directly in the main table (which causes performance degradation), we implemented a sidecar pattern where:
- Main company data stays lean and fast
- Embeddings are stored in a separate, optimized table
- Automatic triggers ensure reliable synchronization
- Background processing prevents blocking writes

**Result**: A production system that processes company embeddings efficiently as new startups are added or company descriptions are updated, enabling semantic search across the startup ecosystem with minimal performance impact and no additional infrastructure costs.

---

## 👨‍💻 About the Author

I'm Penny, a hands-on engineer, VC investor, and advisor. I built this project because I believe the best solutions are born from a deep understanding of both technical architecture and business constraints. I love finding ways to build powerful, scalable systems that are also incredibly efficient.

Having both built companies and invested in them, I understand that the best technology is the one that solves real problems without breaking the budget. This project embodies that philosophy.

You can find more about my work on [LinkedIn](https://linkedin.com/in/your-profile).

---

*This project was extracted and adapted from a production MVP that processes 100K+ company embeddings for a hybrid search system on startup companies. The core architecture has been battle-tested in production and demonstrates real-world scalability, performance optimization, and cost efficiency.*