# STEP 1.2 COMPLETE ✅

## What Was Built

Per-org rate limiting with Redis and token bucket algorithm:

✅ **Redis integration** with connection pooling
✅ **Token bucket rate limiter** - burst + sustained rate
✅ **Per-org limits** - each org has independent bucket
✅ **Rate limit middleware** - automatic enforcement
✅ **Rate limit headers** - X-RateLimit-* on all responses
✅ **Graceful degradation** - fails open if Redis down
✅ **Hard caps** - prevents abuse

## New Files Created

```
src/
├── infra/
│   └── redis.ts                        # Redis client wrapper
├── services/
│   └── rateLimiter.service.ts          # Token bucket algorithm
├── middleware/
│   └── rateLimit.middleware.ts         # Rate limiting middleware
test-rate-limit.sh                       # Test script
```

## Modified Files

- `src/config/env.ts` - Added Redis config
- `src/routes/health.route.ts` - Redis health check
- `src/app.ts` - Added rate limit middleware
- `src/server.ts` - Redis connection lifecycle
- `src/index.ts` - Async server start
- `docker-compose.yml` - Added Redis service
- `.env.example` - Redis connection string

## Token Bucket Algorithm

### How It Works

```
Bucket Capacity: 100 tokens
Refill Rate: 10 tokens/second

Timeline:
T=0s:   [████████████████████] 100 tokens (full)
        Make 100 requests instantly ✅
        
T=0s:   [                    ] 0 tokens (empty)
        Next request → 429 Too Many Requests ❌
        
T=1s:   [██                  ] 10 tokens (refilled)
        Make 10 requests ✅
        
T=10s:  [████████████████████] 100 tokens (full again)

Sustained rate: 10 req/sec (600/min)
Burst capacity: 100 requests
Recovery time: 10 seconds for full bucket
```

### Why Token Bucket?

**Better than fixed windows:**
- ✅ Allows bursts (better UX)
- ✅ Smooth refilling (no thundering herd)
- ✅ Adapts to usage patterns

**Example:**
```
User makes 50 requests at 10:00:00
- Instant success (50 tokens consumed)
- 50 tokens remaining

User waits 5 seconds

At 10:00:05:
- Bucket has 50 + (5 × 10) = 100 tokens (refilled to max)
- Can burst another 50 requests
```

## Setup Instructions

### 1. Start Redis

```bash
# Update docker-compose
docker-compose up -d

# Check Redis is running
docker-compose ps
```

**Expected:**
```
NAME                    STATUS
llm-app-postgres        Up (healthy)
llm-app-redis           Up (healthy)
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Start Server

```bash
npm run dev
```

**Expected logs:**
```
[info]: Starting application...
[info]: Redis connection established
[info]: Redis client ready
[info]: Server running { port: 3000, env: 'development' }
```

## Testing Rate Limiting

### Test 1: Health Check (No Auth = No Rate Limit)

```bash
curl http://localhost:3000/health | jq .
```

**Expected:**
```json
{
  "status": "ok",
  "services": {
    "database": "connected",
    "redis": "connected"
  }
}
```

### Test 2: Authenticated Request (Rate Limit Applied)

```bash
# Get user IDs first
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT id, email, org_id FROM users LIMIT 1;"

# Make request with auth
curl -i \
  -H "x-org-id: <org-id>" \
  -H "x-user-id: <user-id>" \
  http://localhost:3000/health
```

**Expected Response Headers:**
```
HTTP/1.1 200 OK
X-Request-ID: abc-123-def-456
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 99
X-RateLimit-Reset: 2024-02-04T10:30:10.000Z
```

### Test 3: Exhaust Rate Limit

```bash
# Get user IDs
ORG_ID="00000000-0000-0000-0000-000000000001"
USER_ID="<from-database>"

# Run automated test
./test-rate-limit.sh $ORG_ID $USER_ID
```

**Expected output:**
```
🧪 Testing STEP 1.2 - Rate Limiting & Abuse Safety
===================================================

1️⃣  Testing /health (no rate limit)...
connected

2️⃣  Making 5 requests quickly (should succeed)...
  ✅ Request 1: OK
  ✅ Request 2: OK
  ✅ Request 3: OK
  ✅ Request 4: OK
  ✅ Request 5: OK

3️⃣  Rapid fire - 105 requests (should hit rate limit)...
  🚫 First rate limit hit at request 101
  Progress: 20/105 (Success: 20, Rate Limited: 0)
  Progress: 40/105 (Success: 40, Rate Limited: 0)
  Progress: 60/105 (Success: 60, Rate Limited: 0)
  Progress: 80/105 (Success: 80, Rate Limited: 0)
  Progress: 100/105 (Success: 100, Rate Limited: 0)

Final results:
  ✅ Successful:   100
  🚫 Rate limited: 5

✅ Rate limiting is working!
```

### Test 4: Manual Rate Limit Test

```bash
# Spam requests
for i in {1..110}; do
  curl -s -w "%{http_code}\n" -o /dev/null \
    -H "x-org-id: $ORG_ID" \
    -H "x-user-id: $USER_ID" \
    http://localhost:3000/health
done | sort | uniq -c
```

**Expected:**
```
    100 200    # First 100 succeed
     10 429    # Next 10 rate limited
```

### Test 5: Check 429 Response

```bash
# After exhausting rate limit
curl -H "x-org-id: $ORG_ID" -H "x-user-id: $USER_ID" \
  http://localhost:3000/health
```

**Expected:**
```json
{
  "error": "Too Many Requests",
  "message": "Rate limit exceeded. Please try again later.",
  "limit": 100,
  "remaining": 0,
  "resetAt": "2024-02-04T10:30:10.123Z"
}
```

## Rate Limit Configuration

### Current Settings

Located in `src/services/rateLimiter.service.ts`:

```typescript
export const defaultRateLimiter = new RateLimiter({
  maxTokens: 100,      // Burst capacity
  refillRate: 10,      // Tokens per second
  windowSeconds: 60,   // TTL for Redis keys
});
```

### Customizing Limits

**For different tiers:**

```typescript
// Free tier - conservative
const freeTierLimiter = new RateLimiter({
  maxTokens: 20,
  refillRate: 1,       // 60/min
  windowSeconds: 60,
});

// Pro tier - generous
const proTierLimiter = new RateLimiter({
  maxTokens: 500,
  refillRate: 50,      // 3000/min
  windowSeconds: 60,
});

// Enterprise - unlimited
const enterpriseLimiter = new RateLimiter({
  maxTokens: 10000,
  refillRate: 1000,
  windowSeconds: 60,
});
```

**Per-endpoint limits:**

```typescript
// Heavy endpoint (LLM calls)
const llmLimiter = new RateLimiter({
  maxTokens: 10,
  refillRate: 1,       // 60/min
  windowSeconds: 60,
});

// Light endpoint (data fetching)
const dataLimiter = new RateLimiter({
  maxTokens: 1000,
  refillRate: 100,     // 6000/min
  windowSeconds: 60,
});
```

## Redis Data Structure

### Keys Used

```
ratelimit:<org_id>:tokens       # Current token count (float)
ratelimit:<org_id>:lastRefill   # Last refill timestamp (ms)
```

### Example

```bash
# Check rate limit for an org
redis-cli

> GET ratelimit:00000000-0000-0000-0000-000000000001:tokens
"45.7"

> GET ratelimit:00000000-0000-0000-0000-000000000001:lastRefill
"1707044523456"

> TTL ratelimit:00000000-0000-0000-0000-000000000001:tokens
60
```

## Response Headers

All authenticated requests include:

```
X-RateLimit-Limit: 100           # Max tokens in bucket
X-RateLimit-Remaining: 45        # Tokens left
X-RateLimit-Reset: 2024-...      # When bucket will be full
```

Clients can use these to:
- Show users their quota
- Implement client-side throttling
- Schedule retries intelligently

## Graceful Degradation

If Redis fails:

```typescript
// Rate limiter catches errors and fails open
return {
  allowed: true,  // Allow request
  remaining: maxTokens,
  resetAt: new Date(...),
  limit: maxTokens,
};
```

**Why fail open?**
- Availability > strict rate limiting
- Redis downtime shouldn't break your app
- Monitoring will alert you to Redis issues

## Monitoring

### Metrics to Track

1. **Rate limit hits** (429 responses)
2. **Tokens remaining** (average across orgs)
3. **Redis latency** (p95, p99)
4. **Redis connection errors**

### Log Examples

**Request allowed:**
```json
{
  "level": "debug",
  "message": "Rate limit check passed",
  "requestId": "abc-123",
  "orgId": "00000...",
  "remaining": 45
}
```

**Request blocked:**
```json
{
  "level": "warn",
  "message": "Request rate limited",
  "requestId": "abc-123",
  "orgId": "00000...",
  "userId": "user-123",
  "path": "/chat",
  "resetAt": "2024-02-04T10:30:10.000Z"
}
```

## Production Considerations

### 1. Different Limits Per Plan

```typescript
// In middleware, check org tier
const org = await OrgModel.findById(req.context.orgId);

let limiter;
switch (org.plan) {
  case 'free':
    limiter = freeTierLimiter;
    break;
  case 'pro':
    limiter = proTierLimiter;
    break;
  case 'enterprise':
    limiter = enterpriseLimiter;
    break;
}

const result = await limiter.checkLimit(req.context.orgId);
```

### 2. Different Limits Per Endpoint

```typescript
// Create endpoint-specific middleware
export function llmRateLimit() {
  return async (req, res, next) => {
    const result = await llmLimiter.checkLimit(req.context.orgId);
    // ...
  };
}

// Apply to specific routes
app.post('/chat', llmRateLimit(), chatHandler);
```

### 3. Redis Cluster

For production scale:

```typescript
const redis = createClient({
  cluster: {
    nodes: [
      { host: 'redis-1', port: 6379 },
      { host: 'redis-2', port: 6379 },
      { host: 'redis-3', port: 6379 },
    ],
  },
});
```

### 4. Rate Limit by User + Org

```typescript
// Prevent single user from consuming entire org quota
const key = `ratelimit:${orgId}:${userId}`;
```

## Common Issues

### "Rate limit not working"
- Check Redis is running: `docker-compose ps`
- Check Redis connection: `curl http://localhost:3000/health`
- Check auth headers are provided

### "Rate limit too strict"
- Adjust `maxTokens` and `refillRate`
- Consider different limits per tier

### "Rate limit headers missing"
- Only added to authenticated requests
- Check `req.context` is set

---

## 📌 COMMIT CHECKPOINT

You now have:
- Redis connected ✅
- Per-org rate limiting ✅
- Token bucket algorithm ✅
- Hard caps on abuse ✅
- Graceful degradation ✅
- Still no AI, but production-ready abuse prevention ✅

**Next Step: PHASE 2 - STEP 2.1 - Chat API Contract**

We'll add:
- POST /chat endpoint
- Message storage (no LLM yet!)
- Chat history
- Multi-tenant chat isolation

Ready when you are! 🚀