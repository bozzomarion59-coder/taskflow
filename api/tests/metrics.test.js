// Tests des métriques Prometheus : format, labels normalisés, erreurs, logs.
import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { createMemoryRepository } from '../src/repositories/memory.js';

describe('Métriques Prometheus', () => {
  let app;
  let log;
  let repository;

  beforeEach(() => {
    log = vi.fn();
    repository = createMemoryRepository();
    app = createApp({ repository, appEnv: 'test', appVersion: '1.2.3', log });
  });

  const scrape = async () => (await request(app).get('/metrics')).text;

  it('GET /metrics répond 200 au format texte Prometheus', async () => {
    const response = await request(app).get('/metrics');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/plain/);
    expect(response.text).toContain('# TYPE http_requests_total counter');
  });

  it('expose la version et la métrique métier', async () => {
    await request(app).post('/api/tasks').send({ title: 'Mesurer' });

    const text = await scrape();

    expect(text).toContain('taskflow_build_info{version="1.2.3"} 1');
    expect(text).toContain('taskflow_tasks_created_total 1');
  });

  it("utilise la route Express comme label, jamais l'URL réelle", async () => {
    await request(app).post('/api/tasks').send({ title: 'Une tâche' });
    await request(app).patch('/api/tasks/1/toggle');

    const text = await scrape();

    expect(text).toContain('route="/api/tasks"');
    expect(text).toContain('route="/api/tasks/:id/toggle"');
    expect(text).not.toContain('/api/tasks/1');
  });

  it('compte une URL inconnue sous « unmatched »', async () => {
    await request(app).get('/api/inconnu/12345');

    const text = await scrape();

    expect(text).toContain('route="unmatched"');
    expect(text).not.toContain('12345');
  });

  it('compte une réponse 500', async () => {
    repository.list = vi.fn().mockRejectedValue(new Error('base indisponible'));

    const response = await request(app).get('/api/tasks');
    const text = await scrape();

    expect(response.status).toBe(500);
    expect(text).toContain('status_code="500"');
  });

  it("n'appelle pas le logger pour /metrics", async () => {
    await request(app).get('/metrics');

    expect(log).not.toHaveBeenCalled();
  });
});
