import pdfParse from 'pdf-parse';
import logger from '../infra/logger';
import { storageService } from './storage.service';
import { DocumentModel } from '../models/docmuents.model';
import { DocumentChunkModel } from '../models/documentChunk.model';
import { vectorStoreService } from './vectorStore.service';

export interface ParsedDocument {
  text: string;
  numPages: number;
  chunks: Array<{
    content: string;
    page_number: number;
    chunk_index: number;
  }>;
}

/**
 * PDF Parser Service
 * 
 * Extracts text from PDFs and chunks them for processing
 */
export class PDFParserService {
  private chunkSize: number = 400; // chars per chunk
  private chunkOverlap: number = 200; // overlap between chunks

  /**
   * Parse a PDF document
   */
  async parsePDF(storagePath: string): Promise<ParsedDocument> {
    try {
      logger.info('Starting PDF parse', { storagePath });

      // Load PDF from storage
      const pdfBuffer = await storageService.download(storagePath);

      // Parse PDF
      const data = await pdfParse(pdfBuffer);

      logger.info('PDF parsed successfully', {
        storagePath,
        pages: data.numpages,
        textLength: data.text.length,
      });

      // Chunk the text
      const chunks = this.chunkText(data.text);

      return {
        text: data.text,
        numPages: data.numpages,
        chunks: chunks.map((chunk, idx) => ({
          content: chunk,
          page_number: 0, // pdf-parse doesn't give us page-level text easily
          chunk_index: idx,
        })),
      };
    } catch (error) {
      logger.error('PDF parsing failed', { storagePath, error });
      throw error;
    }
  }

  /**
   * Process a document: parse PDF, store chunks, and index vectors
   */
  async processDocument(documentId: string): Promise<void> {
    try {
      logger.info('Processing document', { documentId });

      // Get document from DB
      const document = await DocumentModel.findById(documentId, '00000000-0000-0000-0000-000000000001'); // Note: need proper org filtering
      if (!document) {
        throw new Error('Document not found');
      }

      // Update status to processing
      await DocumentModel.updateStatus(documentId, 'processing');

      // Parse PDF
      const parsed = await this.parsePDF(document.storage_path);

      // Store chunks in database
      const chunks = parsed.chunks.map((chunk, idx) => ({
        document_id: documentId,
        content: chunk.content,
        chunk_index: idx,
        token_count: this.estimateTokens(chunk.content),
      }));

      await DocumentChunkModel.bulkCreate(chunks);

      // Get the created chunks with their IDs
      const createdChunks = await DocumentChunkModel.findByDocumentId(documentId);

      // Index in vector database
      await vectorStoreService.indexChunksBatch(
        createdChunks.map(chunk => ({
          chunkId: chunk.id,
          documentId: documentId,
          content: chunk.content,
          metadata: {
            chunk_index: chunk.chunk_index,
            char_count: chunk.char_count,
            filename: document.original_filename,
          },
        }))
      );

      // Update document status
      await DocumentModel.markParsed(documentId, parsed.numPages);

      logger.info('Document processed successfully', {
        documentId,
        pages: parsed.numPages,
        chunks: chunks.length,
        totalChars: parsed.text.length,
      });
    } catch (error) {
      logger.error('Document processing failed', { documentId, error });

      // Update status to failed
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      await DocumentModel.updateStatus(documentId, 'failed', errorMessage);

      throw error;
    }
  }

  /**
   * Chunk text into overlapping segments
   */
  private chunkText(text: string): string[] {
    const chunks: string[] = [];
    let start = 0;

    while (start < text.length) {
      const end = Math.min(start + this.chunkSize, text.length);
      const chunk = text.slice(start, end);
      chunks.push(chunk);

      // Move forward by (chunkSize - overlap)
      start += this.chunkSize - this.chunkOverlap;

      // Don't create tiny chunks at the end
      if (start >= text.length - this.chunkOverlap) {
        break;
      }
    }

    return chunks;
  }

  /**
   * Estimate token count (rough approximation)
   */
  private estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  /**
   * Get chunks for a document
   */
  async getDocumentChunks(documentId: string): Promise<string[]> {
    const chunks = await DocumentChunkModel.findByDocumentId(documentId);
    return chunks.map(c => c.content);
  }
}

export const pdfParserService = new PDFParserService();
export default pdfParserService;