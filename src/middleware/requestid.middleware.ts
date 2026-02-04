import { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';

// Extend Express Request type to include requestId
declare global {
  namespace Express {
    interface Request {
      requestId: string;
    }
  }
}

export function requestIdMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  // Use existing request ID from header or generate new one
  const requestId = (req.headers['x-request-id'] as string) || uuidv4();
  
  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);
  
  next();
}

export default requestIdMiddleware;