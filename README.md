# LLM Production Application

Production-grade LLM application with multi-tenancy, built step-by-step.

## Current Status: STEP 3.1 ✅ 🎉

**REAL AI IS HERE!**

**Working Features:**
- ✅ Production infrastructure (metrics, logs, auth, rate limiting)
- ✅ PostgreSQL multi-tenant data model
- ✅ Redis with per-org token bucket rate limiting
- ✅ Chat API with message persistence
- ✅ SSE streaming infrastructure
- ✅ **NEW:** Claude API integration (Sonnet 4)
- ✅ **NEW:** Real LLM token streaming
- ✅ **NEW:** Token counting and tracking
- ✅ **NEW:** Budget enforcement (max_tokens)
- ✅ **NEW:** Conversation context (last 20 messages)
- ✅ **NEW:** Error handling for API failures

**This is a fully functional AI chat application!** 🚀

## Setup

1. **Start PostgreSQL:**
```bash
docker-compose up -d
```

2. **Install dependencies:**
```bash
npm install
```

3. **Run database migrations:**
```bash
npm run db:migrate
```

4. **Copy environment file:**
```bash
cp .env.example .env
```

5. **Run in development:**
```bash
npm run dev
```

6. **Test the endpoints:**
```bash
# Health check (no auth)
curl http://localhost:3000/health

# Health check with org context
# First, get user IDs from DB:
docker exec -it llm-app-postgres psql -U postgres -d llm_app -c "SELECT id, email FROM users;"

# Then test with headers
curl -H "x-org-id: <org-id>" -H "x-user-id: <user-id>" http://localhost:3000/health

# Metrics
curl http://localhost:3000/metrics
```

## Endpoints

### GET /health
Returns server health status with request correlation ID.

**Response:**
```json
{
  "status": "ok",
  "env": "development",
  "timestamp": "2024-02-04T10:30:00.000Z",
  "requestId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

### GET /metrics
Returns Prometheus-formatted metrics for scraping.

**Key Metrics:**
- `http_requests_total` - Total HTTP requests by method, route, status
- `http_request_duration_ms` - Request duration histogram
- `http_requests_in_progress` - Current in-flight requests

**Sample Output:**
```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",route="/health",status_code="200"} 5

# HELP http_request_duration_ms Duration of HTTP requests in milliseconds
# TYPE http_request_duration_ms histogram
http_request_duration_ms_bucket{le="5",method="GET",route="/health",status_code="200"} 3
http_request_duration_ms_bucket{le="10",method="GET",route="/health",status_code="200"} 5
```

## Project Structure

```
src/
├── server.ts                    # Server with graceful shutdown
├── app.ts                       # Express app configuration
├── config/
│   └── env.ts                  # Environment variables
├── routes/
│   ├── health.route.ts         # Health check endpoint
│   └── metrics.route.ts        # Prometheus metrics endpoint
├── middleware/
│   ├── requestId.middleware.ts # Request ID correlation
│   └── metrics.middleware.ts   # Metrics collection
├── infra/
│   ├── logger.ts              # Winston logger
│   └── metrics.ts             # Prometheus metrics service
└── index.ts                    # Entry point
```

## Observability Features

### 1. Correlation IDs
Every request gets a unique `requestId` that:
- Is generated automatically (UUID v4)
- Can be provided via `X-Request-ID` header
- Is returned in the `X-Request-ID` response header
- Is included in all logs for that request

### 2. Structured Logging
All logs include:
- `requestId` - Correlation ID
- `method` - HTTP method
- `url` - Request URL
- `route` - Matched route pattern
- `status` - HTTP status code
- `duration` - Request duration in ms
- `userAgent` - Client user agent

### 3. Prometheus Metrics
Production-ready metrics:
- Request counters (total, by route, by status)
- Duration histograms (p50, p95, p99 ready)
- In-progress request gauge (for load monitoring)

## Scripts

- `npm run dev` - Run with hot reload
- `npm run build` - Build for production
- `npm start` - Run production build
- `./test-observability.sh` - Test metrics collection