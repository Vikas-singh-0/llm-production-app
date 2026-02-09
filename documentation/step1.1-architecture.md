# STEP 1.1 Architecture - Multi-Tenancy

## Database Schema

```
┌─────────────────────────────────────────────┐
│              PostgreSQL                     │
│                                             │
│  ┌────────────────────────────────────┐     │
│  │  ORGS                              │     │
│  ├────────────────────────────────────┤     │
│  │ id          UUID (PK)              │     │
│  │ name        VARCHAR                │     │
│  │ slug        VARCHAR (UNIQUE)       │     │
│  │ created_at  TIMESTAMP              │     │
│  │ metadata    JSONB                  │     │
│  └──────────────┬─────────────────────┘     │
│                 │                           │
│                 │ 1:N                       │
│                 ▼                           │
│  ┌────────────────────────────────────┐     │
│  │  USERS                             │     │
│  ├────────────────────────────────────┤     │
│  │ id          UUID (PK)              │     │
│  │ org_id      UUID (FK) ─────────┐   │     │
│  │ email       VARCHAR            │   │     │
│  │ name        VARCHAR            │   │     │
│  │ role        VARCHAR            │   │     │
│  │ created_at  TIMESTAMP          │   │     │
│  │ metadata    JSONB              │   │     │
│  │                                │   │     │
│  │ UNIQUE(org_id, email)          │   │     │
│  └────────────────────────────────┘   │     │
│                                       │     │
└───────────────────────────────────────┼─────┘
                                       
```

## Request Flow with Multi-Tenant Auth

```
┌──────────────────────────────────────────────────────────┐
│  Client Request                                          │
│  Headers:                                                │
│    x-org-id: 00000000-0000-0000-0000-000000000001        │
│    x-user-id: abc-123-def-456                            │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │  requestIdMiddleware   │
        │  • Generate UUID       │
        │  • Set requestId       │
        └────────┬───────────────┘
                 │
                 ▼
        ┌────────────────────────┐
        │  metricsMiddleware     │
        │  • Start timer         │
        │  • Track request       │
        └────────┬───────────────┘
                 │
                 ▼
        ┌────────────────────────────────────────┐
        │  fakeAuthMiddleware                    │
        │  1. Extract x-org-id, x-user-id       │
        │  2. Query: SELECT * FROM users         │
        │     WHERE id = $1                      │
        │  3. Validate: user.org_id == x-org-id │
        │  4. Set req.context:                   │
        │     {                                  │
        │       userId: 'abc-123',               │
        │       orgId: '00000...',               │
        │       role: 'admin',                   │
        │       email: 'user@acme.com'           │
        │     }                                  │
        └────────┬───────────────────────────────┘
                 │
                 ▼
        ┌────────────────────────┐
        │  Route Handler         │
        │  • Access req.context  │
        │  • Filter by orgId     │
        │  • Check role perms    │
        └────────┬───────────────┘
                 │
                 ▼
     ┌───────────────────────┐
     │   Response            │
     │   • Data scoped       │
     │     to org            │
     └───────────────────────┘
```

## Multi-Tenant Isolation Pattern

```
┌─────────────────────────────────────────────────────────┐
│  Tenant 1: Acme Corp (org_id: 0000...0001)             │
│                                                          │
│  Users:                                                  │
│  • admin@acme.com     (admin)                           │
│  • user@acme.com      (member)                          │
│                                                          │
│  Future data (all filtered by org_id):                  │
│  • Chats                                                 │
│  • Documents                                             │
│  • API Keys                                              │
│  • Usage Metrics                                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Tenant 2: Tech Startup (org_id: 0000...0002)          │
│                                                          │
│  Users:                                                  │
│  • founder@techstartup.com  (owner)                     │
│                                                          │
│  Future data (all filtered by org_id):                  │
│  • Chats                                                 │
│  • Documents                                             │
│  • API Keys                                              │
│  • Usage Metrics                                         │
└─────────────────────────────────────────────────────────┘

        ❌ CROSS-TENANT ACCESS BLOCKED ❌
```

## Auth Validation Logic

```
┌──────────────────────────────────────────────────┐
│  Auth Middleware Decision Tree                   │
│                                                   │
│  Path = /health or /metrics?                     │
│  ├─ YES ──> Allow (optional context)             │
│  └─ NO                                            │
│      │                                            │
│      Has x-org-id AND x-user-id?                 │
│      ├─ NO ──> 401 Unauthorized                  │
│      └─ YES                                       │
│          │                                        │
│          Query user from DB                       │
│          ├─ Not found ──> 401 Unauthorized       │
│          └─ Found                                 │
│              │                                    │
│              user.org_id == x-org-id?            │
│              ├─ NO ──> 403 Forbidden             │
│              └─ YES ──> Set req.context ✅       │
│                                                   │
└──────────────────────────────────────────────────┘
```

## Request Context Structure

Every authenticated request has:

```typescript
req.context = {
  userId: "abc-123-def-456",
  orgId: "00000000-0000-0000-0000-000000000001",
  role: "admin",  // or "owner" or "member"
  email: "admin@acme.com"
}
```

This is available in:
- All route handlers
- All middleware (after auth)
- All service functions

## Seed Data

```
Org: Acme Corp (acme-corp)
└─ admin@acme.com (admin)
└─ user@acme.com (member)

Org: Tech Startup Inc (tech-startup)
└─ founder@techstartup.com (owner)
```

## Security Features

✅ **Tenant Isolation**: Users can only access their org's data
✅ **Role-Based Access**: Roles stored, ready for permission checks
✅ **Unique Email per Org**: Same email can exist in different orgs
✅ **Soft Deletes**: deleted_at allows data recovery
✅ **Audit Trail**: created_at, updated_at on all records
✅ **Extensible Metadata**: JSONB for custom fields

## Production-Ready Patterns

1. **Always filter by org_id**
   ```typescript
   // CORRECT
   WHERE org_id = $1 AND ...
   
   // WRONG - leaks data
   WHERE user_id = $1  
   ```

2. **Index on org_id**
   ```sql
   CREATE INDEX idx_users_org_id ON users(org_id);
   ```

3. **Foreign key constraints**
   ```sql
   org_id UUID REFERENCES orgs(id) ON DELETE CASCADE
   ```

4. **Unique constraints per org**
   ```sql
   UNIQUE(org_id, email)
   ```