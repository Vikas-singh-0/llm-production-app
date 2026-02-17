import { QdrantClient } from '@qdrant/js-client-rest';
import { getOllamaService } from './ollama.service';
import logger from '../infra/logger';


export interface VectorSearchResult {
  id: string;
  score: number;
  content: string;
  metadata: Record<string, any>;
}

/**
 * Vector Store Service
 * 
 * Manages vector embeddings and semantic search using Qdrant
 */
export class VectorStoreService {
  private client: QdrantClient;
  private collectionName: string = 'document_chunks';
  private vectorSize: number = 768; // nomic-embed-text dimension

  constructor() {
    // Initialize Qdrant client
    this.client = new QdrantClient({
      url: process.env.QDRANT_URL || 'http://localhost:6333',
      apiKey: process.env.QDRANT_API_KEY,
    });

    logger.info('Vector store service initialized', {
      qdrantUrl: process.env.QDRANT_URL,
      collection: this.collectionName,
      vectorSize: this.vectorSize,
      embeddingModel: 'nomic-embed-text',
    });
  }


  /**
   * Initialize collection if it doesn't exist
   */
  async initializeCollection(): Promise<void> {
    try {
      // Check if collection exists
      const collections = await this.client.getCollections();
      const exists = collections.collections.some(
        c => c.name === this.collectionName
      );

      if (!exists) {
        // Create collection
        await this.client.createCollection(this.collectionName, {
          vectors: {
            size: this.vectorSize,
            distance: 'Cosine',
          },
        });

        logger.info('Vector collection created', {
          collection: this.collectionName,
          vectorSize: this.vectorSize,
        });
      } else {
        logger.info('Vector collection already exists', {
          collection: this.collectionName,
        });
      }
    } catch (error) {
      logger.error('Failed to initialize collection', { error });
      throw error;
    }
  }

  /**
   * Generate embedding for text using nomic-embed-text via Ollama
   */
  private async generateEmbedding(text: string): Promise<number[]> {
    const ollamaService = getOllamaService();
    return await ollamaService.generateEmbedding(text);
  }


  /**
   * Index a document chunk
   */
  async indexChunk(data: {
    chunkId: string;
    documentId: string;
    content: string;
    metadata?: Record<string, any>;
  }): Promise<void> {
    try {
      const embedding = await this.generateEmbedding(data.content);

      await this.client.upsert(this.collectionName, {
        points: [
          {
            id: data.chunkId,
            vector: embedding,
            payload: {
              document_id: data.documentId,
              content: data.content,
              ...data.metadata,
            },
          },
        ],
      });

      logger.debug('Chunk indexed', {
        chunkId: data.chunkId,
        documentId: data.documentId,
        contentLength: data.content.length,
      });
    } catch (error) {
      logger.error('Failed to index chunk', {
        chunkId: data.chunkId,
        error,
      });
      throw error;
    }
  }

  /**
   * Index multiple chunks in batch
   */
  async indexChunksBatch(
    chunks: Array<{
      chunkId: string;
      documentId: string;
      content: string;
      metadata?: Record<string, any>;
    }>
  ): Promise<void> {
    try {
      logger.info('Batch indexing chunks', { count: chunks.length });

      // Generate embeddings for all chunks
      const points = await Promise.all(
        chunks.map(async (chunk) => {
          const embedding = await this.generateEmbedding(chunk.content);
          return {
            id: chunk.chunkId,
            vector: embedding,
            payload: {
              document_id: chunk.documentId,
              content: chunk.content,
              ...chunk.metadata,
            },
          };
        })
      );

      // Batch upsert
      await this.client.upsert(this.collectionName, {
        points,
      });

      logger.info('Batch indexing completed', { count: chunks.length });
    } catch (error) {
      logger.error('Batch indexing failed', { error });
      throw error;
    }
  }

  /**
   * Search for similar chunks
   */
  async search(
    query: string,
    limit: number = 5,
    filter?: Record<string, any>
  ): Promise<VectorSearchResult[]> {
    try {
      logger.info('Vector search started', { query: query.substring(0, 50), limit });

      // Generate query embedding
      const queryEmbedding = await this.generateEmbedding(query);

      // Search in Qdrant
      const results = await this.client.search(this.collectionName, {
        vector: queryEmbedding,
        limit,
        filter: filter ? { must: [filter] } : undefined,
        with_payload: true,
      });

      const searchResults = results.map(result => ({
        id: result.id as string,
        score: result.score,
        content: (result.payload?.content as string) || '',
        metadata: result.payload as Record<string, any>,
      }));

      logger.info('Vector search completed', {
        query: query.substring(0, 50),
        resultsCount: searchResults.length,
      });

      return searchResults;
    } catch (error) {
      logger.error('Vector search failed', { query, error });
      throw error;
    }
  }

  /**
   * Delete chunks for a document
   */
  async deleteDocument(documentId: string): Promise<void> {
    try {
      await this.client.delete(this.collectionName, {
        filter: {
          must: [
            {
              key: 'document_id',
              match: { value: documentId },
            },
          ],
        },
      });

      logger.info('Document vectors deleted', { documentId });
    } catch (error) {
      logger.error('Failed to delete document vectors', { documentId, error });
      throw error;
    }
  }

  /**
   * Get collection info
   */
  async getCollectionInfo(): Promise<{
    vectorsCount: number;
    status: string;
  }> {
    try {
      const info = await this.client.getCollection(this.collectionName);
      return {
        vectorsCount: info.indexed_vectors_count || info.points_count || 0,

        status: info.status,
      };
    } catch (error) {
      logger.error('Failed to get collection info', { error });
      return {
        vectorsCount: 0,
        status: 'error',
      };
    }
  }
}

export const vectorStoreService = new VectorStoreService();
export default vectorStoreService;
