import { Request, Response, NextFunction } from "express";
import { UserModel } from "../models/user.model";
import logger from "../infra/logger";

/**
 * Fake Auth Middleware
 *
 * In production, this would validate JWT tokens, session cookies, etc.
 * For now, it accepts org_id and user_id from headers for testing.
 *
 * Usage:
 *   curl -H "x-org-id: <org-uuid>" -H "x-user-id: <user-uuid>" http://localhost:3000/health
 *
 * This allows us to test multi-tenancy without implementing full auth.
 */
export async function fakeAuthMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    // Extract headers (in production, this would be JWT validation)
    const orgId = req.headers["x-org-id"] as string;
    const userId = req.headers["x-user-id"] as string;

    // For health/metrics endpoints, allow without auth
    if (req.path === "/health" || req.path === "/metrics") {
      // Still set context if headers provided
      if (orgId && userId) {
        const user = await UserModel.findById(userId);

        if (user && user.org_id === orgId) {
          req.context = {
            userId: user.id,
            orgId: user.org_id,
            role: user.role,
            email: user.email,
          };

          logger.debug("Request authenticated", {
            requestId: req.requestId,
            userId: user.id,
            orgId: user.org_id,
            role: user.role,
          });
        }
        if (user.org_id !== orgId) {
          res.status(403).json({
            error: "Forbidden",
            message: "User does not belong to specified organization",
          });
        }

        return next();
      }
      return next();
    }

    // For other endpoints, require auth
    if (!orgId || !userId) {
      res.status(401).json({
        error: "Unauthorized",
        message: "Missing x-org-id or x-user-id headers",
        hint: "In production, this would be JWT auth. For testing, provide headers.",
      });
      return;
    }

    // Validate user exists and belongs to org
    const user = await UserModel.findById(userId);

    if (!user) {
      res.status(401).json({
        error: "Unauthorized",
        message: "User not found",
      });
      return;
    }

    if (user.org_id !== orgId) {
      res.status(403).json({
        error: "Forbidden",
        message: "User does not belong to specified organization",
      });
      return;
    }

    // Set request context
    req.context = {
      userId: user.id,
      orgId: user.org_id,
      role: user.role,
      email: user.email,
    };

    logger.debug("Request authenticated", {
      requestId: req.requestId,
      userId: user.id,
      orgId: user.org_id,
      role: user.role,
    });

    next();
  } catch (error) {
    logger.error("Auth middleware error", {
      requestId: req.requestId,
      error,
    });
    res.status(500).json({
      error: "Internal server error",
      message: "Authentication failed",
    });
  }
}

export default fakeAuthMiddleware;
