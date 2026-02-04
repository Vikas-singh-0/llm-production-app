# LLM Production Application

Production-grade LLM application with multi-tenancy, built step-by-step.

## Current Status: STEP 0.1 ✅

**Working Features:**
- ✅ Node.js + TypeScript server
- ✅ Express app with proper structure
- ✅ Environment configuration
- ✅ Structured JSON logging
- ✅ Graceful shutdown
- ✅ `/health` endpoint

## Setup

1. Install dependencies:
```bash
npm install
```

2. Copy environment file:
```bash
cp .env.example .env
```

3. Run in development:
```bash
npm run dev
```

4. Test the health endpoint:
```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "ok",
  "env": "development",
  "timestamp": "2024-02-04T10:30:00.000Z"
}
```

## Project Structure

```
src/
├── server.ts          # Server with graceful shutdown
├── app.ts             # Express app configuration
├── config/
│   └── env.ts        # Environment variables
├── routes/
│   └── health.route.ts  # Health check endpoint
├── infra/
│   └── logger.ts     # Winston logger
└── index.ts          # Entry point
```

## Scripts

- `npm run dev` - Run with hot reload
- `npm run build` - Build for production
- `npm start` - Run production build