import { Request, Response, Router } from 'express';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import { DocumentModel } from '../models/docmuents.model';
// import { DocumentChunkModel } from '../models/documentChunk.model';
import { storageService } from '../services/storage.service';
// import { documentQueue } from '../services/documentQueue.service';
// import { vectorStoreService } from '../services/vectorStore.service';
import logger from '../infra/logger';

const router = Router();

// Configure multer for file uploads (memory storage)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    // Only allow PDFs for now
    if (file.mimetype === 'application/pdf') {
      cb(null, true);
    } else {
      cb(new Error('Only PDF files are allowed'));
    }
  },
});

/**
 * POST /documents/upload
 * 
 * Upload a document (PDF) and trigger async parsing
 */
router.post('/documents/upload', upload.single('file'), async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    if (!req.file) {
      res.status(400).json({
        error: 'Bad Request',
        message: 'No file provided',
      });
      return;
    }

    logger.info('Document upload started', {
      requestId: req.requestId,
      orgId: req.context.orgId,
      userId: req.context.userId,
      filename: req.file.originalname,
      size: req.file.size,
    });

    // Generate unique filename
    const fileExtension = req.file.originalname.split('.').pop();
    const filename = `${uuidv4()}.${fileExtension}`;

    // Upload to storage
    const storagePath = await storageService.upload(
      filename,
      req.file.buffer,
      req.context.orgId
    );

    // Create database record
    const document = await DocumentModel.create({
      org_id: req.context.orgId,
      user_id: req.context.userId,
      filename,
      original_filename: req.file.originalname,
      mime_type: req.file.mimetype,
      file_size: req.file.size,
      storage_path: storagePath,
      storage_type: 'local',
    });

    // Queue for async parsing
    // const jobId = await documentQueue.addDocument(document.id, req.context.orgId);

    // logger.info('Document uploaded and queued', {
    //   requestId: req.requestId,
    //   documentId: document.id,
    //   jobId,
    // });

    res.status(201).json({
      id: document.id,
      filename: document.original_filename,
      size: document.file_size,
      status: document.status,
      created_at: document.created_at,
    //   job_id: jobId,
    });
  } catch (error) {
    logger.error('Document upload failed', {
      requestId: req.requestId,
      error,
    });

    if (error instanceof Error && error.message === 'Only PDF files are allowed') {
      res.status(400).json({
        error: 'Bad Request',
        message: error.message,
      });
      return;
    }

    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to upload document',
    });
  }
});

/**
 * GET /documents
 * 
 * List user's documents
 */
router.get('/documents', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const documents = await DocumentModel.findByUserId(
      req.context.userId,
      req.context.orgId
    );

    res.status(200).json({
      documents: documents.map(d => ({
        id: d.id,
        filename: d.original_filename,
        size: d.file_size,
        status: d.status,
        page_count: d.page_count,
        created_at: d.created_at,
        parsed_at: d.parsed_at,
      })),
      count: documents.length,
    });
  } catch (error) {
    logger.error('List documents failed', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to list documents',
    });
  }
});

/**
 * GET /documents/:id
 * 
 * Get document details
 */
router.get('/documents/:id', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { id } = req.params;
    const document = await DocumentModel.findById(id, req.context.orgId);

    if (!document) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Document not found',
      });
      return;
    }

    res.status(200).json({
      id: document.id,
      filename: document.original_filename,
      mime_type: document.mime_type,
      size: document.file_size,
      status: document.status,
      page_count: document.page_count,
      created_at: document.created_at,
      parsed_at: document.parsed_at,
      error: document.error_message,
    });
  } catch (error) {
    logger.error('Get document failed', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to get document',
    });
  }
});

/**
 * DELETE /documents/:id
 * 
 * Delete a document
 */
router.delete('/documents/:id', async (req: Request, res: Response) => {
  try {
    if (!req.context) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { id } = req.params;
    const document = await DocumentModel.findById(id, req.context.orgId);

    if (!document) {
      res.status(404).json({
        error: 'Not Found',
        message: 'Document not found',
      });
      return;
    }

    // Delete from storage
    await storageService.delete(document.storage_path);

    // Soft delete from database
    await DocumentModel.delete(id, req.context.orgId);

    logger.info('Document deleted', {
      requestId: req.requestId,
      documentId: id,
    });

    res.status(200).json({
      message: 'Document deleted successfully',
    });
  } catch (error) {
    logger.error('Delete document failed', {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to delete document',
    });
  }
});

/**
 * GET /documents/:id/chunks
 * 
 * Get parsed text chunks from a document
 */
// router.get('/documents/:id/chunks', async (req: Request, res: Response) => {
//   try {
//     if (!req.context) {
//       res.status(401).json({ error: 'Unauthorized' });
//       return;
//     }

//     const { id } = req.params;
//     const document = await DocumentModel.findById(id, req.context.orgId);

//     if (!document) {
//       res.status(404).json({
//         error: 'Not Found',
//         message: 'Document not found',
//       });
//       return;
//     }

//     // Check if document is parsed
//     if (document.status !== 'parsed') {
//       res.status(400).json({
//         error: 'Bad Request',
//         message: `Document is not parsed yet (status: ${document.status})`,
//       });
//       return;
//     }

//     // Get chunks
//     const chunks = await DocumentChunkModel.findByDocumentId(id);

//     res.status(200).json({
//       document_id: id,
//       filename: document.original_filename,
//       chunk_count: chunks.length,
//       chunks: chunks.map(c => ({
//         id: c.id,
//         content: c.content,
//         chunk_index: c.chunk_index,
//         char_count: c.char_count,
//         token_count: c.token_count,
//       })),
//     });
//   } catch (error) {
//     logger.error('Get document chunks failed', {
//       requestId: req.requestId,
//       error,
//     });
//     res.status(500).json({
//       error: 'Internal Server Error',
//       message: 'Failed to get document chunks',
//     });
//   }
// });

/**
 * POST /documents/search
 * 
 * Semantic search across all user's documents
 */
// router.post('/documents/search', async (req: Request, res: Response) => {
//   try {
//     if (!req.context) {
//       res.status(401).json({ error: 'Unauthorized' });
//       return;
//     }

//     const { query, limit } = req.body;

//     if (!query || typeof query !== 'string') {
//       res.status(400).json({
//         error: 'Bad Request',
//         message: 'Query is required',
//       });
//       return;
//     }

//     logger.info('Document search request', {
//       requestId: req.requestId,
//       orgId: req.context.orgId,
//       query: query.substring(0, 50),
//     });

//     // Search in vector DB
//     // In production, filter by org_id for multi-tenancy
//     const results = await vectorStoreService.search(query, limit || 5);

//     logger.info('Search completed', {
//       requestId: req.requestId,
//       resultsCount: results.length,
//     });

//     res.status(200).json({
//       query,
//       results: results.map(r => ({
//         chunk_id: r.id,
//         score: r.score,
//         content: r.content.substring(0, 200) + '...', // Preview
//         full_content: r.content,
//         document_id: r.metadata.document_id,
//         filename: r.metadata.filename,
//       })),
//       count: results.length,
//     });
//   } catch (error) {
//     logger.error('Document search failed', {
//       requestId: req.requestId,
//       error,
//     });
//     res.status(500).json({
//       error: 'Internal Server Error',
//       message: 'Failed to search documents',
//     });
//   }
// });

export default router;