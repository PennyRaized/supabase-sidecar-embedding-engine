-- Document Embeddings Sidecar Table
-- Separate table for storing embeddings to prevent main table bloat and optimize performance
-- This is the core of the sidecar pattern - keeping AI-generated data separate from source data

-- Document embeddings sidecar table (clean, minimal design)
CREATE TABLE IF NOT EXISTS "public"."document_embeddings" (
    "document_id" uuid NOT NULL,
    "source_text" TEXT NOT NULL, -- The actual text that was embedded
    "source_text_hash" TEXT GENERATED ALWAYS AS (md5(source_text)) STORED NOT NULL,
    "embedding" vector(384), -- 384-dimensional vectors from gte-small model
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    
    -- Primary key and foreign key relationship
    CONSTRAINT "document_embeddings_pkey" PRIMARY KEY ("document_id"),
    CONSTRAINT "document_embeddings_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.source_documents(id) ON DELETE CASCADE
);

-- Performance indexes for the sidecar table  
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_source_text_hash" ON "public"."document_embeddings" ("source_text_hash");

-- Vector similarity search index (HNSW for fast similarity queries)
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_vector_cosine" ON "public"."document_embeddings" 
USING hnsw (embedding vector_cosine_ops);

-- Additional vector indexes for different similarity metrics
CREATE INDEX IF NOT EXISTS "idx_document_embeddings_vector_l2" ON "public"."document_embeddings" 
USING hnsw (embedding vector_l2_ops);

-- Foreign key relationship to source documents
ALTER TABLE "public"."document_embeddings" 
ADD CONSTRAINT "fk_document_embeddings_source" 
FOREIGN KEY ("document_id") 
REFERENCES "public"."source_documents" ("document_id") 
ON DELETE CASCADE 
ON UPDATE CASCADE;

-- Grant permissions for the sidecar table
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."document_embeddings" TO service_role;
GRANT USAGE ON SEQUENCE "public"."document_embeddings_id_seq" TO service_role;

-- Create trigger to automatically update updated_at timestamp
CREATE TRIGGER "update_document_embeddings_updated_at" 
    BEFORE UPDATE ON "public"."document_embeddings" 
    FOR EACH ROW 
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Helper function to check if embedding needs updating (change detection)
CREATE OR REPLACE FUNCTION "public"."embedding_needs_update"(
    p_document_id TEXT,
    p_current_content TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    stored_hash TEXT;
    current_hash TEXT;
BEGIN
    -- Calculate hash of current content
    current_hash := md5(p_current_content);
    
    -- Get stored hash for this document
    SELECT source_text_hash INTO stored_hash
    FROM document_embeddings 
    WHERE document_id = p_document_id;
    
    -- Return true if no embedding exists or content has changed
    RETURN (stored_hash IS NULL OR stored_hash != current_hash);
END;
$$;

-- Helper function for semantic search with filters
CREATE OR REPLACE FUNCTION "public"."semantic_search_documents"(
    query_embedding vector(384),
    match_threshold float DEFAULT 0.78,
    match_count int DEFAULT 10,
    filter_document_type text DEFAULT NULL
) RETURNS TABLE (
    document_id text,
    document_type text,
    title text,
    content text,
    similarity float,
    metadata jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sd.document_id,
        sd.document_type,
        sd.title,
        sd.content,
        (1 - (de.embedding <=> query_embedding)) as similarity,
        sd.metadata
    FROM document_embeddings de
    JOIN source_documents sd ON de.document_id = sd.document_id
    WHERE 
        de.embedding IS NOT NULL
        AND (1 - (de.embedding <=> query_embedding)) > match_threshold
        AND (filter_document_type IS NULL OR sd.document_type = filter_document_type)
        AND sd.status = 'active'
    ORDER BY de.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Grant execute permissions on helper functions
GRANT EXECUTE ON FUNCTION "public"."embedding_needs_update" TO service_role;
GRANT EXECUTE ON FUNCTION "public"."semantic_search_documents" TO service_role;

-- Add comprehensive comments explaining the sidecar architecture
COMMENT ON TABLE "public"."document_embeddings" IS 'Sidecar table for document embeddings - keeps AI-generated data separate from source data for optimal performance';
COMMENT ON COLUMN "public"."document_embeddings"."source_text_hash" IS 'MD5 hash of source text for change detection - enables intelligent re-embedding only when content actually changes';
COMMENT ON COLUMN "public"."document_embeddings"."embedding" IS '384-dimensional vector from gte-small model - optimized for semantic search and similarity operations';
COMMENT ON CONSTRAINT "unique_document_embedding" ON "public"."document_embeddings" IS 'Enforces one embedding per document per model - core constraint of the sidecar pattern';
COMMENT ON FUNCTION "public"."embedding_needs_update" IS 'Intelligent change detection - determines if document content has changed and needs re-embedding';
COMMENT ON FUNCTION "public"."semantic_search_documents" IS 'High-performance semantic search with document type filtering and similarity thresholds';

-- Verification queries
SELECT 
    'Document embeddings sidecar created' as status,
    COUNT(*) as initial_embedding_count
FROM document_embeddings;

-- Show the sidecar relationship
SELECT 
    'Sidecar architecture verified' as status,
    EXISTS(
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_document_embeddings_source'
    ) as foreign_key_exists;
