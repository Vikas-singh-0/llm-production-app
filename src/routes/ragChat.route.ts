import { Request, Response, Router } from 'express';
import { ChatModel } from '../models/chat.model';
import { MessageModel } from '../models/message.model';
import { memoryService } from '../services/memory.service';
import { ragService } from '../services/rag.service';
import llmFactory from '../services/llm.factory';
import logger from '../infra/logger';

const router = Router();

/**
 * POST /chat/rag
 * 
 * Chat with RAG (Retrieval Augmented Generation)
 * Searches documents and augments response with context
 */
router.post('/chat/rag', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { message, chat_id } = req.body;

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message is required',
      });
      return;
    }

    logger.info('RAG chat request received', {
      requestId: req.requestId,
      orgId: req.context.orgId,
      userId: req.context.userId,
      chatId: chat_id || 'new',
      messageLength: message.length,
    });

    // Get or create chat
    let chat;
    if (chat_id) {
      chat = await ChatModel.findById(chat_id, req.context.orgId);
      if (!chat) {
        res.status(404).json({
          error: 'Not Found',
          message: 'Chat not found',
        });
        return;
      }
    } else {
      chat = await ChatModel.create({
        org_id: req.context.orgId,
        user_id: req.context.userId,
        title: message.substring(0, 50),
      });
    }

    // Store user message
    await MessageModel.create({
      chat_id: chat.id,
      role: 'user',
      content: message,
      token_count: llmFactory.getProvider().estimateTokens(message),
    });

    // Get conversation history
    const allMessages = await MessageModel.findByChatId(chat.id, 100);
    const { messages: contextMessages } = await memoryService.getContextWindow(
      allMessages,
      chat.id
    );
    const conversationHistory = memoryService.formatForContext(contextMessages);

    // Use RAG to answer
    const ragResponse = await ragService.answerQuestion(message, conversationHistory);

    // Store assistant message
    const assistantMessage = await MessageModel.create({
      chat_id: chat.id,
      role: 'assistant',
      content: ragResponse.answer,
      token_count: llmFactory.getProvider().estimateTokens(ragResponse.answer),
    });

    logger.info('RAG chat completed', {
      requestId: req.requestId,
      chatId: chat.id,
      documentsUsed: ragResponse.context.numDocuments,
      sources: ragResponse.sources.length,
    });

    res.status(200).json({
      chat_id: chat.id,
      message_id: assistantMessage.id,
      reply: ragResponse.answer,
      created_at: assistantMessage.created_at,
      rag_context: {
        documents_used: ragResponse.context.numDocuments,
        sources: ragResponse.sources,
        relevance_scores: ragResponse.context.documents.map(d => ({
          filename: d.filename,
          score: d.score,
        })),
      },
    });
  } catch (error) {
    logger.error('RAG chat error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to process RAG chat request',
    });
  }
});

/**
 * POST /chat/rag/stream
 * 
 * Streaming RAG chat
 */
router.post('/chat/rag/stream', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { message, chat_id } = req.body;

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message is required',
      });
      return;
    }

    logger.info('RAG streaming chat request', {
      requestId: req.requestId,
      orgId: req.context.orgId,
      userId: req.context.userId,
    });

    // Get or create chat
    let chat;
    if (chat_id) {
      chat = await ChatModel.findById(chat_id, req.context.orgId);
      if (!chat) {
        res.status(404).json({ error: 'Not Found', message: 'Chat not found' });
        return;
      }
    } else {
      chat = await ChatModel.create({
        org_id: req.context.orgId,
        user_id: req.context.userId,
        title: message.substring(0, 50),
      });
    }

    // Store user message
    await MessageModel.create({
      chat_id: chat.id,
      role: 'user',
      content: message,
      token_count: llmFactory.getProvider().estimateTokens(message),
    });

    // Get conversation history
    const allMessages = await MessageModel.findByChatId(chat.id, 100);
    const { messages: contextMessages } = await memoryService.getContextWindow(
      allMessages,
      chat.id
    );
    const conversationHistory = memoryService.formatForContext(contextMessages);

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    let fullResponse = '';

    // Stream with RAG
    const ragContext = await ragService.answerQuestionStream(
      message,
      conversationHistory,
      (token) => {
        fullResponse += token;
        if (!res.writableEnded) {
          res.write(`data: ${JSON.stringify({ token, done: false })}\n\n`);
        }
      },
      async (text) => {
        // Send completion with RAG metadata
        if (!res.writableEnded) {
          res.write(`data: ${JSON.stringify({
            token: '',
            done: true,
            fullText: text,
            rag_context: {
              documents_used: ragContext.numDocuments,
              sources: [...new Set(ragContext.documents.map(d => d.filename))],
            },
          })}\n\n`);
        }

        // Store assistant message
        await MessageModel.create({
          chat_id: chat.id,
          role: 'assistant',
          content: text,
          token_count: llmFactory.getProvider().estimateTokens(text),
        });

        res.end();
      }
    );
  } catch (error) {
    logger.error('RAG streaming error', {
      requestId: req.requestId,
      error,
    });
    if (!res.writableEnded) {
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to process RAG streaming request',
      });
    }
  }
});

export default router;
