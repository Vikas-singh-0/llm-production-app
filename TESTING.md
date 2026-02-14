# LLM Production App - Testing Guide

This document contains test cases for all features implemented in the LLM Production App.

## Prerequisites

- Ensure the application is running (see README.md)
- Default base URL: `http://localhost:3000`
- Test org and user IDs from database (or use test script)

## Test Environment Variables

```
bash
# Base URL
BASE_URL="http://localhost:3000"

# Test credentials (replace with actual values from your database)
TEST_ORG_ID="your-org-uuid"
TEST_USER_ID="your-user-uuid"
```

---

## 1. Root Route Tests

### 1.1 GET / (Without Authentication)

```
bash
curl -X GET "${BASE_URL}/"
```

**Expected Response:**
```
json
{
  "message": "Welcome to the LLM Production App",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "requestId": "uuid-here"
}
```

### 1.2 GET / (With Authentication)

```
bash
curl -X GET "${BASE_URL}/" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}"
```

**Expected Response:**
```
json
{
  "message": "Welcome to the LLM Production App",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "requestId": "uuid-here",
  "org": "org-uuid",
  "user": {
    "id": "user-uuid",
    "email": "user@example.com",
    "role": "user"
  },
  "rateLimit": {
    "limit": 100,
    "remaining": 99,
    "resetAt": "2024-01-01T01:00:00.000Z"
  }
}
```

---

## 2. Health Check Tests

### 2.1 GET /health (Without Authentication)

```
bash
curl -X GET "${BASE_URL}/health"
```

**Expected Response (All Services Healthy):**
```
json
{
  "status": "ok",
  "env": "development",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "requestId": "uuid-here",
  "services": {
    "database": "connected",
    "redis": "connected"
  }
}
```

**Expected Response (Degraded - Status 503):**
```
json
{
  "status": "degraded",
  "env": "development",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "requestId": "uuid-here",
  "services": {
    "database": "connected",
    "redis": "disconnected"
  }
}
```

### 2.2 GET /health (With Authentication)

```
bash
curl -X GET "${BASE_URL}/health" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}"
```

**Expected Response:**
```
json
{
  "status": "ok",
  "env": "development",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "requestId": "uuid-here",
  "services": {
    "database": "connected",
    "redis": "connected"
  },
  "org": "org-uuid",
  "user": {
    "id": "user-uuid",
    "email": "user@example.com",
    "role": "user"
  }
}
```

---

## 3. Metrics Tests

### 3.1 GET /metrics

```
bash
curl -X GET "${BASE_URL}/metrics"
```

**Expected Response:** Prometheus metrics format
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/health",status="200"} 10
...
```

---

## 4. Authentication Tests

### 4.1 Unauthorized Access (Missing Headers)

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello"}'
```

**Expected Response (401):**
```
json
{
  "error": "Unauthorized",
  "message": "Missing x-org-id or x-user-id headers",
  "hint": "In production, this would be JWT auth. For testing, provide headers."
}
```

### 4.2 Forbidden Access (Invalid Org)

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: invalid-org-id" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Hello"}'
```

**Expected Response (403):**
```
json
{
  "error": "Forbidden",
  "message": "User does not belong to specified organization"
}
```

---

## 5. Chat API Tests

### 5.1 POST /chat - Create New Chat

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Hello, how are you?"}'
```

**Expected Response:**
```
json
{
  "chat_id": "uuid-here",
  "message_id": "uuid-here",
  "reply": "Chat system online. I received your message: \"Hello, how are you?\"",
  "created_at": "2024-01-01T00:00:00.000Z"
}
```

### 5.2 POST /chat - Validation Error (Empty Message)

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": ""}'
```

**Expected Response (400):**
```
json
{
  "error": "Bad Request",
  "message": "Message is required and must be a non-empty string"
}
```

### 5.3 POST /chat - Validation Error (Message Too Long)

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d "{\"message\": \"$(printf 'a%.0s' {1..10001})\"}"
```

**Expected Response (400):**
```
json
{
  "error": "Bad Request",
  "message": "Message too long (max 10,000 characters)"
}
```

### 5.4 POST /chat - Continue Existing Chat

```
bash
# First, create a chat and save the chat_id
CHAT_ID=$(curl -s -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "First message"}' | jq -r '.chat_id')

# Send follow-up message
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d "{\"message\": \"Second message\", \"chat_id\": \"${CHAT_ID}\"}"
```

### 5.5 POST /chat - Chat Not Found

```
bash
curl -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Hello", "chat_id": "non-existent-chat-id"}'
```

**Expected Response (404):**
```
json
{
  "error": "Not Found",
  "message": "Chat not found or does not belong to your organization"
}
```

---

## 6. Streaming Chat Tests

### 6.1 POST /chat/stream - Basic Streaming

```
bash
curl -X POST "${BASE_URL}/chat/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Tell me a story"}'
```

**Expected Response:** Server-Sent Events (SSE)
```
data: {"token": "This", "done": false}
data: {"token": " ", "done": false}
data: {"token": "is", "done": false}
data: {"token": " ", "done": false}
...
data: {"token": "", "done": true, "fullText": "..."}
```

### 6.2 POST /chat/stream - Using curl with SSE

```
bash
curl -N -X POST "${BASE_URL}/chat/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Hello streaming"}'
```

---

## 7. Get Chat History Tests

### 7.1 GET /chat/:chatId

```
bash
# First create a chat
CHAT_ID=$(curl -s -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Test message for history"}' | jq -r '.chat_id')

# Get chat history
curl -X GET "${BASE_URL}/chat/${CHAT_ID}" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}"
```

**Expected Response:**
```
json
{
  "chat_id": "uuid-here",
  "title": "Test message for history",
  "created_at": "2024-01-01T00:00:00.000Z",
  "updated_at": "2024-01-01T00:00:00.000Z",
  "message_count": 2,
  "messages": [
    {
      "id": "uuid-here",
      "role": "user",
      "content": "Test message for history",
      "created_at": "2024-01-01T00:00:00.000Z"
    },
    {
      "id": "uuid-here",
      "role": "assistant",
      "content": "Chat system online...",
      "created_at": "2024-01-01T00:00:00.000Z"
    }
  ]
}
```

### 7.2 GET /chat/:chatId - Not Found

```
bash
curl -X GET "${BASE_URL}/chat/non-existent-chat-id" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}"
```

**Expected Response (404):**
```
json
{
  "error": "Not Found",
  "message": "Chat not found"
}
```

---

## 8. List Chats Tests

### 8.1 GET /chats

```
bash
curl -X GET "${BASE_URL}/chats" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}"
```

**Expected Response:**
```
json
{
  "chats": [
    {
      "id": "uuid-here",
      "title": "First chat",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z"
    },
    {
      "id": "uuid-here",
      "title": "Second chat",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z"
    }
  ],
  "count": 2
}
```

---

## 9. Rate Limiting Tests

### 9.1 Test Rate Limiting

```
bash
# Make multiple requests to trigger rate limiting
for i in {1..110}; do
  RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X GET "${BASE_URL}/" \
    -H "x-org-id: ${TEST_ORG_ID}" \
    -H "x-user-id: ${TEST_USER_ID}")
  echo "Request $i: $RESPONSE"
done
```

**Expected Behavior:**
- First 100 requests: HTTP 200
- Requests 101+: HTTP 429 (Too Many Requests)

**Expected Response (429):**
```
json
{
  "error": "Too Many Requests",
  "message": "Rate limit exceeded. Please wait before making more requests.",
  "limit": 100,
  "remaining": 0,
  "resetAt": "2024-01-01T01:00:00.000Z"
}
```

---

## 10. Request ID Tests

### 10.1 Verify Request ID is Generated

```
bash
curl -X GET "${BASE_URL}/" | jq '.requestId'
```

Every response should include a unique `requestId` that can be used for tracing.

---

## 11. Comprehensive Test Script

Here's a bash script that runs all tests:

```
bash
#!/bin/bash

BASE_URL="http://localhost:3000"
TEST_ORG_ID="${TEST_ORG_ID:-your-org-uuid}"
TEST_USER_ID="${TEST_USER_ID:-your-user-uuid}"

echo "=== LLM Production App - Test Suite ==="
echo ""

# Test 1: Root route without auth
echo "Test 1.1: GET / (without auth)"
curl -s -X GET "${BASE_URL}/" | jq .
echo ""

# Test 2: Root route with auth
echo "Test 1.2: GET / (with auth)"
curl -s -X GET "${BASE_URL}/" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" | jq .
echo ""

# Test 3: Health check
echo "Test 2: GET /health"
curl -s -X GET "${BASE_URL}/health" | jq .
echo ""

# Test 4: Metrics
echo "Test 3: GET /metrics"
curl -s -X GET "${BASE_URL}/metrics" | head -5
echo ""

# Test 5: Unauthorized access
echo "Test 4.1: POST /chat (unauthorized)"
curl -s -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello"}' | jq .
echo ""

# Test 6: Create new chat
echo "Test 5.1: POST /chat (new chat)"
CHAT_RESPONSE=$(curl -s -X POST "${BASE_URL}/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" \
  -d '{"message": "Hello, how are you?"}')
echo "$CHAT_RESPONSE" | jq .
CHAT_ID=$(echo "$CHAT_RESPONSE" | jq -r '.chat_id')
echo ""

# Test 7: Get chat history
echo "Test 7.1: GET /chat/:chatId"
curl -s -X GET "${BASE_URL}/chat/${CHAT_ID}" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" | jq .
echo ""

# Test 8: List chats
echo "Test 8.1: GET /chats"
curl -s -X GET "${BASE_URL}/chats" \
  -H "x-org-id: ${TEST_ORG_ID}" \
  -H "x-user-id: ${TEST_USER_ID}" | jq .
echo ""

echo "=== Tests Complete ==="
```

---

## 12. Feature Summary

| Feature | Route | Method | Auth Required | Description |
|---------|-------|--------|---------------|-------------|
| Root | `/` | GET | Optional | Welcome message with rate limit status |
| Health | `/health` | GET | Optional | Database and Redis health check |
| Metrics | `/metrics` | GET | No | Prometheus metrics endpoint |
| Create Chat | `/chat` | POST | Yes | Send message, get canned response |
| Stream Chat | `/chat/stream` | POST | Yes | Send message, get streaming response |
| Get Chat | `/chat/:chatId` | GET | Yes | Get chat history |
| List Chats | `/chats` | GET | Yes | List user's chats |
| Rate Limiting | All | All | Yes | Per-org token bucket rate limiting |
| Request ID | All | All | - | Automatic request tracking |

---

## Notes

- All timestamps are in ISO 8601 format
- All responses include a `requestId` for tracing
- The chat system currently returns canned responses (no actual LLM)
- Streaming uses Server-Sent Events (SSE)
- Rate limiting is applied per organization
