import { Registry, Counter, Histogram, Gauge } from 'prom-client';

class MetricsService {
  public readonly registry: Registry;
  public readonly httpRequestDuration: Histogram;
  public readonly httpRequestTotal: Counter;
  public readonly httpRequestsInProgress: Gauge;

  constructor() {
    this.registry = new Registry();

    // HTTP request duration histogram
    this.httpRequestDuration = new Histogram({
      name: 'http_request_duration_ms',
      help: 'Duration of HTTP requests in milliseconds',
      labelNames: ['method', 'route', 'status_code'],
      buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000],
      registers: [this.registry],
    });

    // HTTP request total counter
    this.httpRequestTotal = new Counter({
      name: 'http_requests_total',
      help: 'Total number of HTTP requests',
      labelNames: ['method', 'route', 'status_code'],
      registers: [this.registry],
    });

    // HTTP requests in progress gauge
    this.httpRequestsInProgress = new Gauge({
      name: 'http_requests_in_progress',
      help: 'Number of HTTP requests currently in progress',
      labelNames: ['method', 'route'],
      registers: [this.registry],
    });
  }

  recordRequest(
    method: string,
    route: string,
    statusCode: number,
    durationMs: number
  ): void {
    this.httpRequestDuration
      .labels(method, route, statusCode.toString())
      .observe(durationMs);

    this.httpRequestTotal
      .labels(method, route, statusCode.toString())
      .inc();
  }

  startRequest(method: string, route: string): void {
    this.httpRequestsInProgress.labels(method, route).inc();
  }

  endRequest(method: string, route: string): void {
    this.httpRequestsInProgress.labels(method, route).dec();
  }

  async getMetrics(): Promise<string> {
    return this.registry.metrics();
  }
}

export const metricsService = new MetricsService();
export default metricsService;