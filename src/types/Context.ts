// Request context that carries through the request lifecycle
export interface RequestContext {
  userId: string;
  orgId: string;
  role: 'owner' | 'admin' | 'member';
  email: string;
}

// Extend Express Request type to include context
declare global {
  namespace Express {
    interface Request {
      requestId: string;
      context?: RequestContext;
    }
  }
}

export {};