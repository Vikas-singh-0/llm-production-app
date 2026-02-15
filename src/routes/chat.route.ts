import { Request, Response, Router } from 'express';
import { ChatModel } from '../models/chat.modal';
import { MessageModel } from '../models/message.modal';
import { streamingService } from '../services/streaming.service';
import { geminiService } from '../services/gemini.service';

import logger from '../infra/logger';

const router = Router();

/**
 * POST /chat
 * 
 * Send a message and get a response (non-streaming).
 * Uses real Gemini API.

 */
router.post('/chat', async (req: Request, res: Response) => {
  try {
    // Require authentication
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { message, chat_id } = req.body;

    // Validate input
    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message is required and must be a non-empty string',
      });
      return;
    }

    if (message.length > 10000) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message too long (max 10,000 characters)',
      });
      return;
    }

    logger.info('Chat request received', {
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
          message: 'Chat not found or does not belong to your organization',
        });
        return;
      }
    } else {
      chat = await ChatModel.create({
        org_id: req.context.orgId,
        user_id: req.context.userId,
        title: message.substring(0, 50),
      });
      logger.info('New chat created', {
        requestId: req.requestId,
        chatId: chat.id,
      });
    }

    // Store user message
    const userMessage = await MessageModel.create({
      chat_id: chat.id,
      role: 'user',
      content: message,
      token_count: geminiService.estimateTokens(message),

    });

    // Get recent chat history
    const history = await MessageModel.findRecentByChatId(chat.id, 20);
    const geminiMessages = geminiService.messagesToGeminiFormat(history);

    // Call Gemini API (non-streaming)
    const { text: assistantReply, usage } = await geminiService.chat(geminiMessages);


    // Store assistant message
    const assistantMessage = await MessageModel.create({
      chat_id: chat.id,
      role: 'assistant',
      content: assistantReply,
      token_count: usage.outputTokens,
    });

    logger.info('Chat response generated', {
      requestId: req.requestId,
      chatId: chat.id,
      userMessageId: userMessage.id,
      assistantMessageId: assistantMessage.id,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      totalTokens: usage.totalTokens,
    });

    res.status(200).json({
      chat_id: chat.id,
      message_id: assistantMessage.id,
      reply: assistantReply,
      created_at: assistantMessage.created_at,
      usage: {
        input_tokens: usage.inputTokens,
        output_tokens: usage.outputTokens,
        total_tokens: usage.totalTokens,
      },
    });
  } catch (error) {
    logger.error('Chat endpoint error', {
      requestId: req.requestId,
      error,
    });

    // Check for API errors
    if (error instanceof Error && error.message.includes('API key')) {
      res.status(500).json({
        error: 'Configuration Error',
        message: 'Gemini API not configured. Please set GEMINI_API_KEY.',
      });
      return;
    }


    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to process chat request',
    });
  }
});

/**
 * POST /chat/stream
 * 
 * Send a message and get a streaming response (SSE).
 * Uses real Gemini API with token streaming.

 */
router.post('/chat/stream', async (req: Request, res: Response) => {
  try {
    // Require authentication
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { message, chat_id } = req.body;

    // Validate input
    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message is required and must be a non-empty string',
      });
      return;
    }

    if (message.length > 10000) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Message too long (max 10,000 characters)',
      });
      return;
    }

    logger.info('Streaming chat request received', {
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
      token_count: geminiService.estimateTokens(message),

    });

    // Get recent chat history
    const history = await MessageModel.findRecentByChatId(chat.id, 20);
    const geminiMessages = geminiService.messagesToGeminiFormat(history);

    // Set SSE headers

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    let fullResponse = '';
    let tokenUsage: any = null;

    // Stream from Gemini
    await geminiService.streamChat(geminiMessages, {

      requestId: req.requestId,
      onToken: (token) => {
        fullResponse += token;

        // Send token to client
        if (!res.writableEnded) {
          const eventData = JSON.stringify({
            token,
            done: false,
          });
          res.write(`data: ${eventData}\n\n`);
        }
      },
      onComplete: async (text, usage) => {
        tokenUsage = usage;

        // Send completion event
        if (!res.writableEnded) {
          const completeEvent = JSON.stringify({
            token: '',
            done: true,
            fullText: text,
            usage: {
              input_tokens: usage.inputTokens,
              output_tokens: usage.outputTokens,
              total_tokens: usage.totalTokens,
            },
          });
          res.write(`data: ${completeEvent}\n\n`);
        }

        // Store assistant message
        try {
          await MessageModel.create({
            chat_id: chat.id,
            role: 'assistant',
            content: text,
            token_count: usage.outputTokens,
          });

          logger.info('Streaming chat completed', {
            requestId: req.requestId,
            chatId: chat.id,
            responseLength: text.length,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            totalTokens: usage.totalTokens,
          });
        } catch (error) {
          logger.error('Failed to store streamed message', {
            requestId: req.requestId,
            error,
          });
        }

        res.end();
      },
      onError: (error) => {
        logger.error('Streaming error', {
          requestId: req.requestId,
          error,
        });

        if (!res.writableEnded) {
          const errorEvent = JSON.stringify({
            error: 'Stream failed',
            message: error.message,
          });
          res.write(`data: ${errorEvent}\n\n`);
          res.end();
        }
      },
    });
  } catch (error) {
    logger.error('Streaming chat endpoint error', {
      requestId: req.requestId,
      error,
    });

    if (!res.writableEnded) {
    if (error instanceof Error && error.message.includes('API key')) {
        res.status(500).json({
          error: 'Configuration Error',
          message: 'Gemini API not configured. Please set GEMINI_API_KEY.',
        });
      } else {

        res.status(500).json({
          error: 'Internal Server Error',
          message: 'Failed to process streaming chat request',
        });
      }
    }
  }
});

/**
 * GET /chat/:chatId
 * 
 * Get chat history
 */
router.get('/chat/:chatId', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { chatId } = req.params;

    // Verify chat exists and belongs to org
    const chat = await ChatModel.findById(chatId, req.context.orgId);
    if (!chat) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Chat not found',
      });
      return;
    }

    // Get messages
    const messages = await MessageModel.findByChatId(chatId);

    res.status(200).json({
      chat_id: chat.id,
      title: chat.title,
      created_at: chat.created_at,
      updated_at: chat.updated_at,
      message_count: messages.length,
      messages: messages.map(m => ({
        id: m.id,
        role: m.role,
        content: m.content,
        created_at: m.created_at,
      })),
    });
  } catch (error) {
    logger.error('Get chat error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to retrieve chat',
    });
  }
});

/**
 * GET /chats
 * 
 * List user's chats
 */
router.get('/chats', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const chats = await ChatModel.findByUserId(
      req.context.userId,
      req.context.orgId
    );

    res.status(200).json({
      chats: chats.map(c => ({
        id: c.id,
        title: c.title,
        created_at: c.created_at,
        updated_at: c.updated_at,
      })),
      count: chats.length,
    });
  } catch (error) {
    logger.error('List chats error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to retrieve chats',
    });
  }
});

export default router;
