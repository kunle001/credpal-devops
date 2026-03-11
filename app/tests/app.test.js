const request = require('supertest');
const app = require('../src/index');

describe('GET /health', () => {
  it('returns 200 with healthy status', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('timestamp');
  });
});

describe('GET /status', () => {
  it('returns 200 with app status', async () => {
    const res = await request(app).get('/status');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body).toHaveProperty('version');
    expect(res.body).toHaveProperty('environment');
    expect(res.body.dependencies).toHaveProperty('database');
  });
});

describe('POST /process', () => {
  it('processes a valid JSON payload', async () => {
    const payload = { customerId: 'cust_001', amount: 50000 };
    const res = await request(app)
      .post('/process')
      .send(payload)
      .set('Content-Type', 'application/json');

    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('processed');
    expect(res.body.data).toEqual(payload);
  });

  it('returns 400 when body is empty', async () => {
    const res = await request(app)
      .post('/process')
      .send({})
      .set('Content-Type', 'application/json');

    expect(res.statusCode).toBe(400);
    expect(res.body).toHaveProperty('error');
  });
});

describe('Unknown routes', () => {
  it('returns 404 for unknown paths', async () => {
    const res = await request(app).get('/unknown');
    expect(res.statusCode).toBe(404);
  });
});
