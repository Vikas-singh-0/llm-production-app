import { Request, Response, Router } from 'express';
import { ChatModel } from '../models/chat.model';
import { MessageModel } from '../models/message.model';
import { streamingService } from '../services/streaming.service';
import { llmFactory } from '../services/llm.factory';
import { memoryService } from '../services/memory.service';
import logger from '../infra/logger';

const router = Router();

/**
 * POST /chat
 * 
 * Send a message and get a response (non-streaming).
 * Uses real gemini API.
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
      token_count: llmFactory.getProvider().estimateTokens(message),
    });

    // Get all messages and apply sliding window with summary
    const allMessages = await MessageModel.findByChatId(chat.id, 100);
    
    // Check if we should create a summary
    if (memoryService.shouldSummarize(allMessages)) {
      try {
        await memoryService.summarizeConversation(allMessages, chat.id);
        logger.info('Auto-summarization triggered', {
          requestId: req.requestId,
          chatId: chat.id,
          messageCount: allMessages.length,
        });
      } catch (error) {
        logger.error('Auto-summarization failed', {
          requestId: req.requestId,
          chatId: chat.id,
          error,
        });
        // Continue without summary
      }
    }
    
    const { messages: contextMessages, summary, totalTokens, truncated } = 
      await memoryService.getContextWindow(allMessages, chat.id);
    
    logger.debug('Context prepared for non-streaming', {
      requestId: req.requestId,
      totalMessages: allMessages.length,
      contextMessages: contextMessages.length,
      totalTokens,
      truncated,
      hasSummary: !!summary,
    });

    const providerMessages = memoryService.formatMessagesForProvider(contextMessages, summary);

    // Call LLM API (non-streaming) with fallback
    const { text: assistantReply, usage } = await llmFactory.chatWithFallback(providerMessages);

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
        message: 'gemini API not configured. Please set ANTHROPIC_API_KEY.',
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
 * Uses real gemini API with token streaming.
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
      token_count: llmFactory.getProvider().estimateTokens(message),
    });

    // Get all messages and apply sliding window with summary
    const allMessages = await MessageModel.findByChatId(chat.id, 100);
    
    // Check if we should create a summary
    if (memoryService.shouldSummarize(allMessages)) {
      try {
        await memoryService.summarizeConversation(allMessages, chat.id);
        logger.info('Auto-summarization triggered', {
          requestId: req.requestId,
          chatId: chat.id,
          messageCount: allMessages.length,
        });
      } catch (error) {
        logger.error('Auto-summarization failed', {
          requestId: req.requestId,
          chatId: chat.id,
          error,
        });
        // Continue without summary
      }
    }
    
    const { messages: contextMessages, summary, totalTokens, truncated } = 
      await memoryService.getContextWindow(allMessages, chat.id);
    
    logger.debug('Context prepared for streaming', {
      requestId: req.requestId,
      totalMessages: allMessages.length,
      contextMessages: contextMessages.length,
      totalTokens,
      truncated,
      hasSummary: !!summary,
    });

    const providerMessages = memoryService.formatMessagesForProvider(contextMessages, summary);

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    let fullResponse = '';
    let tokenUsage: any = null;

    // Stream from LLM provider with fallback
    await llmFactory.streamChatWithFallback(providerMessages, {
      requestId: req.requestId,
      onToken: (token: string) => {
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
      onComplete: async (text: string, usage: any) => {
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
      onError: (error: Error) => {
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
          message: 'gemini API not configured. Please set ANTHROPIC_API_KEY.',
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

/**
 * POST /chats
 * 
 * Create a new empty chat
 */
router.post('/chats', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { title } = req.body;

    const chat = await ChatModel.create({
      org_id: req.context.orgId,
      user_id: req.context.userId,
      title: title || 'New Chat',
    });

    logger.info('New chat created via POST /chats', {
      requestId: req.requestId,
      chatId: chat.id,
    });

    res.status(201).json({
      id: chat.id,
      title: chat.title,
      created_at: chat.created_at,
      updated_at: chat.updated_at,
    });
  } catch (error) {
    logger.error('Create chat error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to create chat',
    });
  }
});

/**
 * PUT /chat/:chatId
 * 
 * Update chat title
 */
router.put('/chat/:chatId', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { chatId } = req.params;
    const { title } = req.body;

    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Title is required and must be a non-empty string',
      });
      return;
    }

    const chat = await ChatModel.updateTitle(chatId, req.context.orgId, title);
    
    if (!chat) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Chat not found or does not belong to your organization',
      });
      return;
    }

    logger.info('Chat title updated', {
      requestId: req.requestId,
      chatId: chat.id,
      newTitle: title,
    });

    res.status(200).json({
      id: chat.id,
      title: chat.title,
      created_at: chat.created_at,
      updated_at: chat.updated_at,
    });
  } catch (error) {
    logger.error('Update chat error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to update chat',
    });
  }
});

/**
 * DELETE /chat/:chatId
 * 
 * Delete a chat
 */
router.delete('/chat/:chatId', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { chatId } = req.params;

    const deleted = await ChatModel.delete(chatId, req.context.orgId);
    
    if (!deleted) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Chat not found or does not belong to your organization',
      });
      return;
    }

    logger.info('Chat deleted', {
      requestId: req.requestId,
      chatId: chatId,
    });

    res.status(200).json({
      message: 'Chat deleted successfully',
    });
  } catch (error) {
    logger.error('Delete chat error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to delete chat',
    });
  }
});

/**
 * GET /chats/org
 * 
 * Get all chats for an organization
 */
router.get('/chats/org', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const chats = await ChatModel.findByOrgId(req.context.orgId);

    res.status(200).json({
      chats: chats.map(c => ({
        id: c.id,
        title: c.title,
        user_id: c.user_id,
        created_at: c.created_at,
        updated_at: c.updated_at,
      })),
      count: chats.length,
    });
  } catch (error) {
    logger.error('List org chats error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to retrieve organization chats',
    });
  }
});

/**
 * GET /chat/:chatId/messages
 * 
 * Get messages for a chat
 */
router.get('/chat/:chatId/messages', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { chatId } = req.params;
    const limit = parseInt(req.query.limit as string) || 100;

    // Verify chat exists and belongs to org
    const chat = await ChatModel.findById(chatId, req.context.orgId);
    if (!chat) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Chat not found',
      });
      return;
    }

    const messages = await MessageModel.findByChatId(chatId, limit);

    res.status(200).json({
      chat_id: chat.id,
      message_count: messages.length,
      messages: messages.map(m => ({
        id: m.id,
        role: m.role,
        content: m.content,
        token_count: m.token_count,
        created_at: m.created_at,
      })),
    });
  } catch (error) {
    logger.error('Get messages error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to retrieve messages',
    });
  }
});

/**
 * GET /chat/:chatId/messages/count
 * 
 * Get message count for a chat
 */
router.get('/chat/:chatId/messages/count', async (req: Request, res: Response) => {
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

    const count = await MessageModel.countByChatId(chatId);

    res.status(200).json({
      chat_id: chatId,
      message_count: count,
    });
  } catch (error) {
    logger.error('Get message count error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get message count',
    });
  }
});

/**
 * DELETE /chat/:chatId/messages/:messageId
 * 
 * Delete a message from a chat
 */
router.delete('/chat/:chatId/messages/:messageId', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { chatId, messageId } = req.params;

    // Verify chat exists and belongs to org
    const chat = await ChatModel.findById(chatId, req.context.orgId);
    if (!chat) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Chat not found',
      });
      return;
    }

    // Verify message exists
    const message = await MessageModel.findById(messageId);
    if (!message || message.chat_id !== chatId) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Message not found',
      });
      return;
    }

    // Delete the message
    const deletedCount = await MessageModel.deleteByChatId(chatId);

    logger.info('Message deleted', {
      requestId: req.requestId,
      chatId: chatId,
      messageId: messageId,
    });

    res.status(200).json({
      message: 'Message deleted successfully',
    });
  } catch (error) {
    logger.error('Delete message error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to delete message',
    });
  }
});

export default router;
