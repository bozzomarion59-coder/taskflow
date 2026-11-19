// Métriques Prometheus de l'API : RED (débit, erreurs, durée) + une métrique métier.
// Chaque appel crée son PROPRE registre : les tests créent une application neuve
// sans heurter le registre global de prom-client.
import client from 'prom-client';

export function createMetrics({
  appVersion = 'dev',
  collectDefaults = true,
} = {}) {
  const register = new client.Registry();
  if (collectDefaults) client.collectDefaultMetrics({ register });

  const labelNames = ['method', 'route', 'status_code'];

  const httpRequests = new client.Counter({
    name: 'http_requests_total',
    help: 'Nombre de requêtes HTTP traitées',
    labelNames,
    registers: [register],
  });

  const httpDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durée des requêtes HTTP en secondes',
    labelNames,
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [register],
  });

  const tasksCreated = new client.Counter({
    name: 'taskflow_tasks_created_total',
    help: 'Nombre de tâches créées',
    registers: [register],
  });

  const buildInfo = new client.Gauge({
    name: 'taskflow_build_info',
    help: "Version de l'application en ligne (toujours 1)",
    labelNames: ['version'],
    registers: [register],
  });
  buildInfo.set({ version: appVersion }, 1);

  // Cardinalité : on utilise la route Express (/api/tasks/:id/toggle),
  // jamais l'URL réelle (/api/tasks/42/toggle).
  function routeLabel(req) {
    if (!req.route) return 'unmatched';
    const path = `${req.baseUrl}${req.route.path}`;
    return path.length > 1 && path.endsWith('/') ? path.slice(0, -1) : path;
  }

  function middleware(req, res, next) {
    const stopTimer = httpDuration.startTimer();
    // Les labels sont calculés à la FIN de la réponse : la route est alors connue.
    res.on('finish', () => {
      const labels = {
        method: req.method,
        route: routeLabel(req),
        status_code: res.statusCode,
      };
      httpRequests.inc(labels);
      stopTimer(labels);
    });
    next();
  }

  async function handler(_req, res) {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  }

  return {
    register,
    middleware,
    handler,
    taskCreated: () => tasksCreated.inc(),
  };
}
