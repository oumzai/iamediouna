// اختبار محلي للخادم الوسيط دون اتصال حقيقي بـ Claude API:  node backend/test_worker.mjs
import worker from './worker.js';
import assert from 'node:assert/strict';

const env = { ANTHROPIC_API_KEY: 'test-key', ACCESS_TOKENS: 'school-1:TOKEN-12345678', MODEL: 'claude-sonnet-5-5' };
let lastRequest = null;

globalThis.fetch = async (url, init) => {
  lastRequest = { url, body: JSON.parse(init.body), headers: init.headers };
  const body = lastRequest.body;
  const prompt = body.messages[0].content.at(-1).text;
  let text;
  if (prompt.includes('{"questions"')) {
    text = '```json\n' + JSON.stringify({
      questions: [
        { type: 'single', prompt: 'من بطل القصة؟', options: [{ label: 'الأرنب', correct: true }, { label: 'الذئب', correct: false }, { label: 'القط', correct: false }], difficulty: 1, skill: 'شخصية', source_ref: 'ص 1' },
        { type: 'truefalse', prompt: 'نام الأرنب تحت الشجرة.', options: [{ label: 'صح', correct: true }, { label: 'خطأ', correct: false }] },
        { type: 'order', prompt: 'رتب الأحداث', options: [{ label: 'أ' }, { label: 'ب' }, { label: 'ج' }] },
        { type: 'single', prompt: 'سؤال بدون جواب صحيح', options: [{ label: 'x' }, { label: 'y' }] },
        { type: 'short', prompt: 'ماذا تعلمت؟', keywords: ['الصبر'] },
      ],
    }) + '\n```';
  } else if (prompt.includes('{"question"')) {
    text = JSON.stringify({ question: { type: 'multi', prompt: 'اختر الأماكن', options: [{ label: 'الغابة', correct: true }, { label: 'البحر', correct: false }] } });
  } else {
    text = JSON.stringify({ config: { minStoriesMonthly: 2, wComprehension: 60 }, rationale: 'تعليل' });
  }
  return new Response(JSON.stringify({ content: [{ type: 'thinking', thinking: '...' }, { type: 'text', text }] }), { status: 200 });
};

const call = (path, body, token = 'TOKEN-12345678', method = 'POST') =>
  worker.fetch(new Request('https://x.test' + path, {
    method,
    headers: { 'Content-Type': 'application/json', 'X-Access-Token': token },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  }), env);

const pdf = 'JVBERi0xLjQK'.repeat(20);

let r = await call('/v1/health', null, 'bad-token-xxx', 'GET');
assert.equal(r.status, 401);

r = await call('/v1/health', null, 'TOKEN-12345678', 'GET');
assert.equal(r.status, 200);

r = await call('/v1/generate-quiz', { pdf_base64: pdf, title: 'الأرنب', level: 1, count: 5, types: ['single', 'truefalse', 'order', 'short'] });
assert.equal(r.status, 200);
let data = await r.json();
assert.equal(data.questions.length, 4, 'السؤال بدون جواب صحيح يجب أن يُستبعد');
assert.equal(lastRequest.headers['anthropic-version'], '2023-06-01');
assert.equal(lastRequest.body.messages[0].content[0].type, 'document');
assert.equal(lastRequest.body.messages[0].content[0].source.media_type, 'application/pdf');
assert.ok(!JSON.stringify(lastRequest.body).includes('massar'), 'لا بيانات تلاميذ');

r = await call('/v1/regenerate-question', { pdf_base64: pdf, title: 'الأرنب', level: 3, type: 'multi', avoid: ['من بطل القصة؟'] });
data = await r.json();
assert.equal(data.question.type, 'multi');

r = await call('/v1/suggest-criteria', { stats: { students: 25 } });
data = await r.json();
assert.equal(data.config.minStoriesMonthly, 2);

r = await call('/v1/generate-quiz', { title: 'بدون ملف' });
assert.equal(r.status, 400);

console.log('✔ جميع اختبارات الخادم الوسيط نجحت');
