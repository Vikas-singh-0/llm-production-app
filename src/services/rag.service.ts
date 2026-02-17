import { vectorStoreService } from './vectorStore.service';
import llmFactory from './llm.factory';
import logger from '../infra/logger';

export interface RAGContext {
  query: string;
  documents: Array<{
    content: string;
    filename: string;
    score: number;
  }>;
  numDocuments: number;
}

export interface RAGResponse {
  answer: string;
  context: RAGContext;
  sources: string[];
}

/**
 * RAG Service
 * 
 * Retrieval Augmented Generation:
 * 1. Search for relevant document chunks
 * 2. Add them as context to prompt
 * 3. Generate answer using LLM Factory (supports multiple providers)
 */
export class RAGService {
  private readonly maxContextChunks = 5;

  /**
   * Answer a question using RAG
   */
  async answerQuestion(
    query: string,
    conversationHistory: any[] = []
  ): Promise<RAGResponse> {

    try {
      logger.info('RAG query started', {
        query: query.substring(0, 100),
      });

      // 1. Retrieve relevant document chunks
      const searchResults = await vectorStoreService.search(
        query,
        this.maxContextChunks
      );

      if (searchResults.length === 0) {
        logger.warn('No relevant documents found', { query });
        
        // No documents found - answer without RAG
        const messages = [
          ...conversationHistory,
          { role: 'user' as const, content: query },
        ];

        const response = await llmFactory.getProvider().chat(messages);

        return {
          answer: response.text,
          context: {
            query,
            documents: [],
            numDocuments: 0,
          },
          sources: [],
        };
      }

      // 2. Build context from retrieved chunks
      const contextDocs = searchResults.map((result, idx) => ({
        content: result.content,
        filename: result.metadata.filename || 'Unknown',
        score: result.score,
        index: idx + 1,
      }));

      const contextText = contextDocs
        .map(
          (doc, idx) =>
            `[Document ${idx + 1}: ${doc.filename}]\n${doc.content}\n`
        )
        .join('\n---\n\n');

      // 3. Create enhanced prompt with context
      const augmentedQuery = this.buildRAGPrompt(query, contextText);

      // 4. Generate answer using LLM Factory
      const messages = [
        ...conversationHistory,
        { role: 'user' as const, content: augmentedQuery },
      ];

      const response = await llmFactory.getProvider().chat(messages);

      // 5. Extract unique sources
      const sources = [...new Set(contextDocs.map(d => d.filename))];

      logger.info('RAG query completed', {
        query: query.substring(0, 100),
        documentsUsed: searchResults.length,
        sources: sources.length,
        answerLength: response.text.length,
      });

      return {
        answer: response.text,
        context: {
          query,
          documents: contextDocs,
          numDocuments: searchResults.length,
        },
        sources,
      };
    } catch (error) {
      logger.error('RAG query failed', { query, error });
      throw error;
    }
  }

  /**
   * Stream answer with RAG
   */
  async answerQuestionStream(
    query: string,
    conversationHistory: any[],
    onToken: (token: string) => void,
    onComplete: (fullText: string) => void
  ): Promise<RAGContext> {

    try {
      logger.info('RAG streaming query started', {
        query: query.substring(0, 100),
      });

      // 1. Retrieve relevant document chunks
      const searchResults = await vectorStoreService.search(
        query,
        this.maxContextChunks
      );

      let contextText = '';
      let contextDocs: Array<{ content: string; filename: string; score: number }> = [];

      if (searchResults.length > 0) {
        // Build context from retrieved chunks
        contextDocs = searchResults.map((result) => ({
          content: result.content,
          filename: result.metadata.filename || 'Unknown',
          score: result.score,
        }));

        contextText = contextDocs
          .map(
            (doc, idx) =>
              `[Document ${idx + 1}: ${doc.filename}]\n${doc.content}\n`
          )
          .join('\n---\n\n');
      }

      // 2. Create enhanced prompt
      const augmentedQuery = searchResults.length > 0
        ? this.buildRAGPrompt(query, contextText)
        : query;

      // 3. Stream answer using LLM Factory
      const messages = [
        ...conversationHistory,
        { role: 'user' as const, content: augmentedQuery },
      ];

      await llmFactory.getProvider().streamChat(messages, {
        requestId: 'rag-stream',
        onToken,
        onComplete: (fullText, usage) => {
          logger.info('RAG streaming completed', {
            query: query.substring(0, 100),
            documentsUsed: searchResults.length,
            tokens: usage.totalTokens,
          });
          onComplete(fullText);
        },
      });

      return {
        query,
        documents: contextDocs,
        numDocuments: searchResults.length,
      };
    } catch (error) {
      logger.error('RAG streaming failed', { query, error });
      throw error;
    }
  }

  /**
   * Build RAG-enhanced prompt
   */
  private buildRAGPrompt(query: string, context: string): string {
    return `You are a helpful AI assistant. Answer the user's question based on the provided document excerpts.

IMPORTANT INSTRUCTIONS:
- Use the document excerpts below to inform your answer
- If the answer is in the documents, cite which document number you're referencing
- If the answer is not in the documents, say so and provide a general answer
- Be concise but comprehensive
- Don't make up information not present in the documents

DOCUMENT EXCERPTS:
${context}

---

USER QUESTION:
${query}

Please provide a clear, accurate answer based on the documents above.`;
  }

  /**
   * Check if query is document-related
   */
  isDocumentQuery(query: string): boolean {
    const documentKeywords = [
      'document',
      'file',
      'pdf',
      'uploaded',
      'in the',
      'according to',
      'what does it say',
      'summarize',
      'extract',
    ];

    const lowerQuery = query.toLowerCase();
    return documentKeywords.some(keyword => lowerQuery.includes(keyword));
  }
}

export const ragService = new RAGService();
export default ragService;
