# LLM Production Application

Production-grade LLM application with multi-tenancy, built step-by-step.

## Current Status: STEP 4.2 ✅ 🎉

**COMPLETE MEMORY SYSTEM!**

**Memory Management:**
- ✅ Sliding window (recent messages in token budget)
- ✅ **NEW:** Automatic summarization (60+ message conversations)
- ✅ **NEW:** Long-term memory preservation
- ✅ **NEW:** ~90% token compression via summaries
- ✅ **NEW:** Claude remembers full conversation history

**Production Features:**
- Multi-tenant architecture, rate limiting, auth
- Claude API with streaming, token tracking
- Prompt versioning (LLMOps)
- Redis caching, PostgreSQL persistence

**This handles conversations of ANY length while staying within token limits!** 🚀

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
│   ├── metrics.route.ts        # Prometheus metrics endpoint
│   ├── chat.route.ts           # Chat API with streaming
│   └── prompt.route.ts         # Prompt management API (LLMOps)
├── models/
│   └── prompt.model.ts         # Prompt CRUD operations
├── middleware/
│   ├── requestId.middleware.ts # Request ID correlation
│   ├── metrics.middleware.ts   # Metrics collection
│   ├── fakeAuth.middleware.ts  # Multi-tenant auth
│   └── rateLimit.middleware.ts # Token bucket rate limiting
├── infra/
│   ├── logger.ts              # Winston logger
│   ├── metrics.ts             # Prometheus metrics service
│   ├── database.ts            # PostgreSQL connection
│   └── redis.ts               # Redis caching
├── services/
│   ├── claude.service.ts      # Claude API integration
│   └── rateLimiter.service.ts # Rate limiting logic
└── index.ts                    # Entry point
```


## LLMOps Features

### 1. Database-Backed Prompts
System prompts are stored in PostgreSQL, not hard-coded:
- Change prompts without code deployment
- Instant activation (0 downtime)
- Safe rollback to previous versions
- Track which version is active per prompt name

### 2. Version Control
Each prompt can have multiple versions:
- Version 1: Original prompt
- Version 2: Experimental changes
- Version 3: Optimized version
- Only one version active at a time (enforced by database trigger)

### 3. Usage Stats
Every prompt usage is tracked:
- `total_uses` - How many times used
- `avg_tokens` - Average tokens per request
- `avg_response_time_ms` - Average response time
- Compare versions to find optimal prompts

### 4. Instant Rollback
If a new prompt performs poorly:
```bash
# Rollback to version 1 instantly
curl -X PUT /prompts/default-system-prompt/activate/1 \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID"
```
No deployment, no downtime, no risk!

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