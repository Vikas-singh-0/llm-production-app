# STEP 1.2 Architecture - Rate Limiting

## Token Bucket Algorithm Visualization

```
┌─────────────────────────────────────────────────────┐
│  Token Bucket for Org: 00000...0001                 │
│                                                      │
│  Capacity: 100 tokens                               │
│  Refill:   10 tokens/second                         │
│                                                      │
│  ┌──────────────────────────────────────────┐      │
│  │  Current State                            │      │
│  │  ████████████████████████████             │      │
│  │  ↑                           ↑            │      │
│  │  0                          100           │      │
│  │                                           │      │
│  │  Tokens: 70                               │      │
│  │  Last refill: 10:30:00.000                │      │
│  └──────────────────────────────────────────┘      │
│                                                      │
│  Actions:                                           │
│  • Request comes in   → Consume 1 token            │
│  • Time passes        → Refill tokens               │
│  • Bucket full        → Stop refilling              │
│  • Bucket empty       → Return 429                  │
└─────────────────────────────────────────────────────┘
```

## Request Flow with Rate Limiting

```
┌──────────────────────────────────────────────┐
│  Client Request                               │
│  POST /chat                                   │
│  Headers: x-org-id, x-user-id                │
└───────────────┬──────────────────────────────┘
                │
                ▼
   ┌────────────────────────┐
   │  requestIdMiddleware   │
   │  • Generate UUID       │
   └────────┬───────────────┘
            │
            ▼
   ┌────────────────────────┐
   │  metricsMiddleware     │
   │  • Start timer         │
   └────────┬───────────────┘
            │
            ▼
   ┌────────────────────────────┐
   │  fakeAuthMiddleware        │
   │  • Validate user           │
   │  • Set req.context         │
   └────────┬───────────────────┘
            │
            ▼
   ┌────────────────────────────────────────────┐
   │  rateLimitMiddleware                       │
   │                                             │
   │  1. Skip if /health or /metrics            │
   │  2. Get org_id from req.context            │
   │  3. Query Redis:                           │
   │     key = "ratelimit:{org_id}:tokens"      │
   │                                             │
   │  4. Calculate current tokens:              │
   │     timePassed = now - lastRefill          │
   │     tokensToAdd = timePassed × refillRate  │
   │     currentTokens = min(max, old + new)    │
   │                                             │
   │  5. Can consume 1 token?                   │
   │     ├─ YES: tokens -= 1                    │
   │     │       Update Redis                    │
   │     │       Set headers                     │
   │     │       next() ✅                       │
   │     │                                       │
   │     └─ NO:  Return 429 ❌                  │
   │             X-RateLimit-Reset              │
   │                                             │
   └────────┬───────────────────────────────────┘
            │
            ▼ (if allowed)
   ┌────────────────────────┐
   │  Route Handler         │
   │  • Process request     │
   └────────────────────────┘
```

## Redis Data Flow

```
┌──────────────────────────────────────────────────┐
│  Redis                                            │
│                                                   │
│  Keys per org:                                   │
│                                                   │
│  ratelimit:org-1:tokens      → "75.3"           │
│  ratelimit:org-1:lastRefill  → "1707044523456"  │
│                                                   │
│  ratelimit:org-2:tokens      → "100.0"          │
│  ratelimit:org-2:lastRefill  → "1707044523000"  │
│                                                   │
│  TTL on all keys: 60 seconds                    │
│  (Auto-cleanup of inactive orgs)                │
│                                                   │
└──────────────────────────────────────────────────┘

Algorithm Timeline:

T=0ms:    Request arrives
T=1ms:    GET ratelimit:org-1:tokens → "75.3"
          GET ratelimit:org-1:lastRefill → "1707044523000"
T=2ms:    Calculate:
          - Time passed: 456ms = 0.456s
          - Tokens to add: 0.456 × 10 = 4.56
          - New tokens: 75.3 + 4.56 = 79.86
          - Consume 1: 79.86 - 1 = 78.86
T=3ms:    SET ratelimit:org-1:tokens "78.86" EX 60
          SET ratelimit:org-1:lastRefill "1707044523456" EX 60
T=4ms:    Return success with headers
```

## Multi-Tenant Isolation

```
┌────────────────────────────────────────┐
│  Org 1: Acme Corp                      │
│  Bucket: 100 tokens                    │
│                                         │
│  User A makes 50 requests  → 50 left  │
│  User B makes 30 requests  → 20 left  │
│  User C makes 20 requests  → 0 left   │
│  User D makes 1 request    → 429 ❌   │
│                                         │
│  (All users share org bucket)          │
└────────────────────────────────────────┘

┌────────────────────────────────────────┐
│  Org 2: Tech Startup                   │
│  Bucket: 100 tokens                    │
│                                         │
│  User E makes 10 requests  → 90 left  │
│                                         │
│  (Independent bucket - unaffected)     │
└────────────────────────────────────────┘

❌ NO CROSS-ORG INTERFERENCE
```

## Rate Limit Response Headers

```
Every authenticated response includes:

┌────────────────────────────────────────────┐
│  HTTP/1.1 200 OK                           │
│                                             │
│  X-Request-ID: abc-123-def-456             │
│  X-RateLimit-Limit: 100                    │
│  X-RateLimit-Remaining: 78                 │
│  X-RateLimit-Reset: 2024-02-04T10:30:10Z  │
│                                             │
│  Content-Type: application/json            │
│  ...                                        │
└────────────────────────────────────────────┘

Client can use these to:
1. Show quota in UI
2. Implement client-side throttling
3. Calculate retry timing
4. Display "X requests remaining"
```

## 429 Rate Limit Response

```
┌────────────────────────────────────────────┐
│  HTTP/1.1 429 Too Many Requests            │
│                                             │
│  X-Request-ID: abc-123-def-456             │
│  X-RateLimit-Limit: 100                    │
│  X-RateLimit-Remaining: 0                  │
│  X-RateLimit-Reset: 2024-02-04T10:30:10Z  │
│                                             │
│  Content-Type: application/json            │
│                                             │
│  {                                          │
│    "error": "Too Many Requests",           │
│    "message": "Rate limit exceeded...",    │
│    "limit": 100,                           │
│    "remaining": 0,                         │
│    "resetAt": "2024-02-04T10:30:10.123Z"  │
│  }                                          │
└────────────────────────────────────────────┘
```

## Burst vs Sustained Rate

```
Token Bucket: 100 tokens, 10/sec refill

Scenario 1: Burst Traffic
──────────────────────────
T=0s:   Make 100 requests instantly
        [████████████████████] → [                    ]
        ✅ All succeed (burst capacity)

T=0s:   Make 1 more request
        ❌ 429 Too Many Requests

T=1s:   Bucket has 10 tokens (refilled)
        Make 10 requests ✅

T=2s:   Bucket has 10 tokens
        Make 10 requests ✅

Sustained rate: 10 req/sec


Scenario 2: Steady Traffic
──────────────────────────
T=0s:   Make 5 requests
        [████████████████████] → [██████████████████  ]
        95 tokens left

T=1s:   Bucket refills to 100 (hit max)
        [████████████████████]

T=2s:   Make 5 requests
        [██████████████████  ]
        95 tokens left

Can maintain this indefinitely


Scenario 3: Idle Recovery
──────────────────────────
T=0s:   Make 100 requests
        [                    ] 0 tokens

T=0s-10s: No requests (idle)

T=10s:  Bucket fully refilled
        [████████████████████] 100 tokens
        Ready for next burst ✅
```

## Graceful Degradation

```
┌─────────────────────────────────────────┐
│  What happens if Redis fails?           │
│                                          │
│  ❌ Redis connection error               │
│                                          │
│  Rate limiter catches error:             │
│                                          │
│  try {                                   │
│    await redis.get(key)                  │
│  } catch (error) {                       │
│    logger.error('Redis error', error)    │
│                                          │
│    // FAIL OPEN - allow request         │
│    return {                              │
│      allowed: true,                      │
│      remaining: maxTokens,               │
│      resetAt: new Date(...),             │
│      limit: maxTokens                    │
│    }                                     │
│  }                                       │
│                                          │
│  Result: ✅ Request proceeds             │
│          ⚠️  But unmetered               │
│          📊 Monitoring alerts you        │
└─────────────────────────────────────────┘

Why fail open?
- Availability > strict rate limiting
- Better UX during incidents
- Monitoring catches the issue
- Short outage won't break your product
```

## Middleware Stack Order

```
CRITICAL: Order matters!

1. express.json()           ← Parse body
2. express.urlencoded()     ← Parse form data
3. requestIdMiddleware      ← Set correlation ID
4. metricsMiddleware        ← Start tracking
5. fakeAuthMiddleware       ← Set req.context
6. rateLimitMiddleware      ← Check org quota ⭐
7. Route handlers           ← Your endpoints

Why this order?
- Need requestId for logging
- Need context for org_id
- Rate limit before expensive work
- Fail fast if over quota
```

## Production Scaling

```
Single Redis:
┌─────────────┐
│   Redis     │  ← All orgs
└─────────────┘
Max: ~10,000 req/sec


Redis Cluster:
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Redis 1    │  │  Redis 2    │  │  Redis 3    │
│  Orgs 1-100 │  │ Orgs 101-200│  │ Orgs 201-300│
└─────────────┘  └─────────────┘  └─────────────┘
Max: 100,000+ req/sec


With Cache:
┌─────────────┐
│  App Server │
│  + Cache    │  ← Hot orgs in memory
└──────┬──────┘
       │ Cache miss only
       ▼
┌─────────────┐
│   Redis     │
└─────────────┘
Max: 50,000+ req/sec per server
```
