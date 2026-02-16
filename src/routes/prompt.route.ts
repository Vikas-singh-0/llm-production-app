import { Request, Response, Router } from 'express';
import { PromptModel } from '../models/prompt.model';
import logger from '../infra/logger';

const router = Router();

/**
 * GET /prompts
 * 
 * List all prompt names
 */
router.get('/prompts', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const names = await PromptModel.listNames();

    res.status(200).json({
      prompts: names,
      count: names.length,
    });
  } catch (error) {
    logger.error('List prompts error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list prompts',
    });
  }
});

/**
 * GET /prompts/:name
 * 
 * Get all versions of a prompt
 */
router.get('/prompts/:name', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { name } = req.params;
    const versions = await PromptModel.getAllVersions(name);

    if (versions.length === 0) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Prompt not found',
      });
      return;
    }

    res.status(200).json({
      name,
      versions: versions.map(v => ({
        version: v.version,
        content: v.content,
        is_active: v.is_active,
        created_at: v.created_at,
        metadata: v.metadata,
        stats: v.stats,
      })),
      active_version: versions.find(v => v.is_active)?.version || null,
    });
  } catch (error) {
    logger.error('Get prompt versions error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get prompt versions',
    });
  }
});

/**
 * POST /prompts
 * 
 * Create new prompt version
 * 
 * Body:
 *   {
 *     "name": "default-system-prompt",
 *     "content": "You are a helpful assistant...",
 *     "is_active": false,
 *     "metadata": {}
 *   }
 */
router.post('/prompts', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    // Only admins can create prompts
    if (req.context.role !== 'admin' && req.context.role !== 'owner') {
      res.status(403).json({
        error: 'Forbidden',
        message: 'Only admins can create prompts',
      });
      return;
    }

    const { name, content, is_active, metadata } = req.body;

    if (!name || !content) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Name and content are required',
      });
      return;
    }

    const prompt = await PromptModel.create({
      name,
      content,
      is_active: is_active || false,
      created_by: req.context.userId,
      metadata: metadata || {},
    });

    logger.info('Prompt created', {
      requestId: req.requestId,
      userId: req.context.userId,
      promptId: prompt.id,
      name: prompt.name,
      version: prompt.version,
    });

    res.status(201).json({
      id: prompt.id,
      name: prompt.name,
      version: prompt.version,
      content: prompt.content,
      is_active: prompt.is_active,
      created_at: prompt.created_at,
    });
  } catch (error) {
    logger.error('Create prompt error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to create prompt',
    });
  }
});

/**
 * PUT /prompts/:name/activate/:version
 * 
 * Activate a specific prompt version
 */
router.put('/prompts/:name/activate/:version', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    // Only admins can activate prompts
    if (req.context.role !== 'admin' && req.context.role !== 'owner') {
      res.status(403).json({
        error: 'Forbidden',
        message: 'Only admins can activate prompts',
      });
      return;
    }

    const { name, version } = req.params;
    const versionNum = parseInt(version, 10);

    if (isNaN(versionNum)) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Version must be a number',
      });
      return;
    }

    const prompt = await PromptModel.activate(name, versionNum);

    if (!prompt) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Prompt version not found',
      });
      return;
    }

    logger.info('Prompt activated', {
      requestId: req.requestId,
      userId: req.context.userId,
      promptId: prompt.id,
      name: prompt.name,
      version: prompt.version,
    });

    res.status(200).json({
      message: 'Prompt activated',
      name: prompt.name,
      version: prompt.version,
      is_active: prompt.is_active,
    });
  } catch (error) {
    logger.error('Activate prompt error', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to activate prompt',
    });
  }
});

export default router;