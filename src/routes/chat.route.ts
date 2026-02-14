import { Request, Response, Router } from 'express';
import { ChatModel } from '../models/chat.modal';
import { MessageModel } from '../models/message.modal';
import { streamingService } from '../services/streaming.service';
import logger from '../infra/logger';

const router = Router();

/**
 * POST /chat
 * 
 * Send a message and get a response.
 * For now, returns a canned response (no LLM).
 * 
 * Body:
 *   {
 *     "message": "Hello, how are you?",
 *     "chat_id": "optional-existing-chat-id"
 *   }
 * 
 * Response:
 *   {
 *     "chat_id": "uuid",
 *     "message_id": "uuid",
 *     "reply": "Chat system online. I received your message.",
 *     "created_at": "2024-02-04T10:30:00.000Z"
 *   }
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
      // Verify chat exists and belongs to this org
      chat = await ChatModel.findById(chat_id, req.context.orgId);
      if (!chat) {
        res.status(404).json({
          error: 'Not Found',
          message: 'Chat not found or does not belong to your organization',
        });
        return;
      }
    } else {
      // Create new chat
      chat = await ChatModel.create({
        org_id: req.context.orgId,
        user_id: req.context.userId,
        title: message.substring(0, 50), // First 50 chars as title
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
    });

    // Generate canned response (no LLM yet!)
    const assistantReply = `Chat system online. I received your message: "${message.substring(0, 50)}${message.length > 50 ? '...' : ''}"`;

    // Store assistant message
    const assistantMessage = await MessageModel.create({
      chat_id: chat.id,
      role: 'assistant',
      content: assistantReply,
    });

    logger.info('Chat response generated', {
      requestId: req.requestId,
      chatId: chat.id,
      userMessageId: userMessage.id,
      assistantMessageId: assistantMessage.id,
    });

    res.status(200).json({
      chat_id: chat.id,
      message_id: assistantMessage.id,
      reply: assistantReply,
      created_at: assistantMessage.created_at,
    });
  } catch (error) {
    logger.error('Chat endpoint error', {
      requestId: req.requestId,
      error,
    });
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
 * Simulates token-by-token streaming without LLM.
 * 
 * Body:
 *   {
 *     "message": "Hello, how are you?",
 *     "chat_id": "optional-existing-chat-id"
 *   }
 * 
 * Response: Server-Sent Events
 *   data: {"token": "Hello", "done": false}
 *   data: {"token": " ", "done": false}
 *   data: {"token": "world", "done": false}
 *   data: {"token": "", "done": true, "fullText": "Hello world"}
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
    });

    // Generate response text (simulated)
    const responseText = `This is a simulated streaming response to your message. Each word will arrive separately, simulating how a real LLM would stream tokens. Your message was: "${message.substring(0, 100)}${message.length > 100 ? '...' : ''}"`;

    // Accumulate full response for storage
    let fullResponse = '';

    // Stream response
    await streamingService.streamResponse(res, responseText, {
      requestId: req.requestId,
      onToken: (token) => {
        fullResponse += token;
      },
      onComplete: async () => {
        // Store assistant message after streaming completes
        try {
          await MessageModel.create({
            chat_id: chat.id,
            role: 'assistant',
            content: fullResponse,
          });

          logger.info('Streaming chat completed', {
            requestId: req.requestId,
            chatId: chat.id,
            responseLength: fullResponse.length,
          });
        } catch (error) {
          logger.error('Failed to store streamed message', {
            requestId: req.requestId,
            error,
          });
        }
      },
      onError: (error) => {
        logger.error('Streaming error', {
          requestId: req.requestId,
          error,
        });
      },
    });
  } catch (error) {
    logger.error('Streaming chat endpoint error', {
      requestId: req.requestId,
      error,
    });

    if (!res.writableEnded) {
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to process streaming chat request',
      });
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