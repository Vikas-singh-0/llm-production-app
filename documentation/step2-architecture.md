# STEP 0.2 Architecture

## Request Flow with Observability

```
┌─────────────┐
│   Client    │
│  (curl/app) │
└──────┬──────┘
       │ GET /health
       │ Header: X-Request-ID (optional)
       ▼
┌──────────────────────────────────────────┐
│         Express Application              │
│                                          │
│  ┌────────────────────────────────┐    │
│  │  1. requestIdMiddleware        │    │
│  │     • Generate/extract UUID    │    │
│  │     • Set req.requestId        │    │
│  │     • Set X-Request-ID header  │    │
│  └────────────┬───────────────────┘    │
│               ▼                          │
│  ┌────────────────────────────────┐    │
│  │  2. metricsMiddleware          │    │
│  │     • Start timer               │    │
│  │     • Increment in-progress    │    │
│  │     • On response:              │    │
│  │       - Record duration         │    │
│  │       - Increment counter       │    │
│  │       - Decrement in-progress  │    │
│  │       - Log with requestId     │    │
│  └────────────┬───────────────────┘    │
│               ▼                          │
│  ┌────────────────────────────────┐    │
│  │  3. Route Handler              │    │
│  │     • /health → health.route   │    │
│  │     • /metrics → metrics.route │    │
│  └────────────┬───────────────────┘    │
│               ▼                          │
└──────────────┬───────────────────────────┘
               │
               ▼
       ┌───────────────┐
       │   Response    │
       │ + X-Request-ID│
       └───────────────┘

```

## Metrics Storage

```
┌─────────────────────────────────────┐
│      Prometheus Registry            │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ http_requests_total          │  │
│  │ (Counter)                    │  │
│  │ Labels: method,route,status  │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ http_request_duration_ms     │  │
│  │ (Histogram)                  │  │
│  │ Buckets: 5,10,25,50,100...   │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ http_requests_in_progress    │  │
│  │ (Gauge)                      │  │
│  │ Current: 0                   │  │
│  └──────────────────────────────┘  │
│                                     │
└─────────────┬───────────────────────┘
              │
              │ GET /metrics
              ▼
        ┌──────────────┐
        │  Prometheus  │
        │   Scraper    │
        └──────────────┘
```

## Log Output

```
Console (Development)
┌──────────────────────────────────────────────────────┐
│ 2024-02-04T10:30:05.123Z [info]: HTTP Request        │
│ {                                                     │
│   requestId: 'a1b2-c3d4-e5f6-7890',                 │
│   method: 'GET',                                     │
│   url: '/health',                                    │
│   route: '/health',                                  │
│   status: 200,                                       │
│   duration: '4ms',                                   │
│   userAgent: 'curl/7.68.0',                         │
│   service: 'llm-app'                                │
│ }                                                     │
└──────────────────────────────────────────────────────┘

JSON (Production - for log aggregation)
┌──────────────────────────────────────────────────────┐
│ {"timestamp":"2024-02-04T10:30:05.123Z",            │
│  "level":"info",                                     │
│  "message":"HTTP Request",                          │
│  "requestId":"a1b2-c3d4-e5f6-7890",                │
│  "method":"GET",                                     │
│  "url":"/health",                                    │
│  "route":"/health",                                  │
│  "status":200,                                       │
│  "duration":"4ms",                                   │
│  "userAgent":"curl/7.68.0",                         │
│  "service":"llm-app"}                               │
└──────────────────────────────────────────────────────┘
```

## Middleware Order (Critical!)

```
1. express.json()              # Parse body
2. express.urlencoded()        # Parse form data
3. requestIdMiddleware         # FIRST - set correlation ID
4. metricsMiddleware           # SECOND - track everything
5. Route handlers              # Your actual endpoints
```

**Why this order matters:**
- Request ID must be set BEFORE any logging
- Metrics middleware needs Request ID to log properly
- Both must run BEFORE route handlers