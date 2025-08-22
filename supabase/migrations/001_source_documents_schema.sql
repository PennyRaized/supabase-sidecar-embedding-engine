-- Source Documents Schema
-- Generic document storage table for any type of content that needs embeddings
-- Refactored from company-specific schema to support any document type

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pgmq";

-- Main source documents table (clean, minimal schema)
-- Uses simple 'content' field as single source of truth for embeddings
CREATE TABLE IF NOT EXISTS "public"."source_documents" (
    "id" uuid DEFAULT gen_random_uuid() NOT NULL,
    "content" TEXT NOT NULL, -- Single source of truth for embedding generation
    "metadata" JSONB DEFAULT '{}'::jsonb,
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT "source_documents_pkey" PRIMARY KEY ("id")
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS "idx_source_documents_created_at" ON "public"."source_documents" ("created_at");
CREATE INDEX IF NOT EXISTS "idx_source_documents_updated_at" ON "public"."source_documents" ("updated_at");

-- Full-text search index on content
CREATE INDEX IF NOT EXISTS "idx_source_documents_content_fts" ON "public"."source_documents" 
USING gin(to_tsvector('english', content));

-- Metadata search index  
CREATE INDEX IF NOT EXISTS "idx_source_documents_metadata_gin" ON "public"."source_documents" 
USING gin(metadata);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON "public"."source_documents" TO service_role;

-- Add helpful comments explaining the clean design
COMMENT ON TABLE "public"."source_documents" IS 'Clean document storage - content is single source of truth for embeddings';
COMMENT ON COLUMN "public"."source_documents"."content" IS 'The text content that will be used for embedding generation';
COMMENT ON COLUMN "public"."source_documents"."metadata" IS 'Optional JSON field for document-specific attributes';

-- Create function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER "update_source_documents_updated_at" 
    BEFORE UPDATE ON "public"."source_documents" 
    FOR EACH ROW 
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Verification query
SELECT 
    'Clean source documents schema created' as status,
    'content column is single source of truth' as architecture_note;
