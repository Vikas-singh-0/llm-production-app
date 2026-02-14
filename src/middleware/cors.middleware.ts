import { Request, Response, NextFunction } from 'express';

/**
 * CORS Middleware
 * 
 * Enables Cross-Origin Resource Sharing for the API.
 * This allows browser-based clients to make requests to the API.
 */
export function corsMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  // Allow requests from any origin (for development)
  // In production, you might want to restrict this to specific domains
  res.header('Access-Control-Allow-Origin', '*');
  
  // Allow these headers
  res.header('Access-Control-Allow-Headers', 
    'Origin, X-Requested-With, Content-Type, Accept, Authorization, x-org-id, x-user-id'
  );
  
  // Allow these methods
  res.header('Access-Control-Allow-Methods', 
    'GET, POST, PUT, DELETE, OPTIONS, PATCH'
  );
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
    return;
  }
  
  next();
}

export default corsMiddleware;
