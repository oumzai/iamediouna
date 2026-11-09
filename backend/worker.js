/**
 * الخادم الوسيط لتطبيق «مكتبتي الصفية الذكية» — Cloudflare Worker.
 *
 * لماذا خادم وسيط؟
 *  - مفتاح Claude API السري يبقى هنا فقط (متغير سري ANTHROPIC_API_KEY)، ولا يوجد أبدًا داخل تطبيق Android.
 *  - كل مؤسسة تحصل على «رمز وصول» (ACCESS_TOKENS) يمكن إلغاؤه في أي وقت.
 *  - التطبيق لا يرسل أي معلومة عن التلاميذ: فقط ملف القصة PDF ومستوى القسم.
 *
 * المسارات:
 *   GET  /v1/health
 *   POST /v1/generate-quiz        { pdf_base64, title, language, level, difficulty, count, types[] }
 *   POST /v1/regenerate-question  { pdf_base64, title, language, level, type, difficulty, avoid[] }
 *   POST /v1/suggest-criteria     { stats }
 *
 * المتغيرات (wrangler secret put / wrangler.toml):
 *   ANTHROPIC_API_KEY  (سري)
 *   ACCESS_TOKENS      (سري) رموز مفصولة بفواصل، مثال: "mediouna-school-1:XXXX,mediouna-school-2:YYYY"
 *   MODEL              (اختياري) الافتراضي claude-sonnet-5-5
 */

const DEFAULT_MODEL = 'claude-sonnet-5-5';
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MAX_PDF_BASE64 = 32 * 1024 * 1024; // حد الطلب لدى Claude API (32 ميغابايت)

const TYPE_NAMES = {
  single: 'اختيار من متعدد بجواب صحيح واحد (3 أو 4 اختيارات)',
  multi: 'خانات اختيار: أكثر من جواب صحيح (4 اختيارات، 2 أو 3 صحيحة)',
  truefalse: 'صح أو خطأ',
  image: 'اختيار صورة: الاختيارات وصف قصير لصور سيضيفها الأستاذ (شخصيات، أماكن، أشياء من القصة)',
  order: 'ترتيب أحداث القصة (3 إلى 5 أحداث بالترتيب الصحيح)',
  complete: 'إكمال جملة من القصة بكلمة مناسبة (اختيار من متعدد)',
  short: 'سؤال بجواب قصير مكتوب، مع كلمات مفتاحية للتصحيح',
};

const LEVEL_GUIDE = {
  1: 'المستوى الأول ابتدائي (6-7 سنوات): جمل قصيرة جدًا، كلمات بسيطة، الحد الأدنى من الكتابة، أسئلة عن الشخصيات والأماكن والأحداث الظاهرة، تفضيل أسئلة الصور وصح/خطأ.',
  2: 'المستوى الثاني ابتدائي (7-8 سنوات): أسئلة قصيرة ومباشرة، اختيارات بسيطة، صور واضحة، ترتيب 3 أحداث.',
  3: 'المستوى الثالث ابتدائي (8-9 سنوات): أسئلة مباشرة ومتوسطة، تسلسل الأحداث، فهم الشخصيات والأسباب البسيطة.',
  4: 'المستوى الرابع ابتدائي (9-10 سنوات): فهم الشخصيات ودوافعها، الأسباب والنتائج، ترتيب 4 أحداث.',
  5: 'المستوى الخامس ابتدائي (10-11 سنة): فهم عميق، استنتاج، معاني الكلمات في السياق، الفكرة العامة.',
  6: 'المستوى السادس ابتدائي (11-12 سنة): استنتاج وتأويل، ربط الأسباب بالنتائج، العبرة والفكرة العامة، معاني الكلمات.',
};

const SYSTEM_PROMPT = `أنت خبير تربوي في تقييم الفهم القرائي لدى تلاميذ التعليم الابتدائي بالمغرب.
مهمتك: إعداد أسئلة تقيس هل قرأ التلميذ القصة الورقية فعلًا وفهمها، وتميز بين الفهم السطحي والفهم الجيد.
قواعد صارمة:
1. كل سؤال يجب أن يستند إلى محتوى القصة المرفقة فقط. ممنوع اختراع معلومات غير موجودة فيها.
2. تجنب الأسئلة التي يمكن الإجابة عنها من العنوان أو الغلاف أو بالتخمين العام.
3. نوّع بين أسئلة الأحداث، الشخصيات، الأماكن، الترتيب، الأسباب، والاستنتاج حسب المستوى.
4. الاختيارات الخاطئة يجب أن تكون معقولة ومن عالم القصة، لكنها خاطئة بوضوح لمن قرأها.
5. اكتب بلغة القصة (العربية الفصحى المبسطة للقصص العربية، والفرنسية للقصص الفرنسية).
6. لكل سؤال حدد المرجع: رقم الصفحة أو مقطعًا قصيرًا (أقل من 10 كلمات) من القصة يثبت الجواب.
7. أجب بصيغة JSON فقط، دون أي نص قبلها أو بعدها.`;

const QUESTION_SCHEMA = `كل سؤال كائن JSON بهذه الحقول:
{
  "type": "single|multi|truefalse|image|order|complete|short",
  "prompt": "نص السؤال",
  "options": [{"label": "نص الاختيار", "correct": true|false}],   // لـ order: الأحداث بالترتيب الصحيح، و correct=false للجميع
  "keywords": ["كلمة1", "كلمة2"],                                   // لـ short فقط
  "image_hint": "وصف الصورة المطلوبة",                               // لـ image فقط (اختياري)
  "difficulty": 1|2|3,
  "skill": "حدث|شخصية|مكان|ترتيب|سبب|استنتاج|مفردات|فكرة عامة",
  "source_ref": "ص 3: «...»"
}
لـ truefalse: options = [{"label":"صح","correct":..},{"label":"خطأ","correct":..}]. لـ short: options = [].`;

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
    const url = new URL(request.url);
    try {
      const token = request.headers.get('X-Access-Token') || '';
      if (!checkToken(token, env)) return json({ error: 'رمز الوصول غير صحيح.' }, 401);

      if (request.method === 'GET' && url.pathname === '/v1/health') {
        return json({ ok: true, model: env.MODEL || DEFAULT_MODEL });
      }
      if (request.method !== 'POST') return json({ error: 'مسار غير معروف.' }, 404);

      const body = await request.json();
      if (url.pathname === '/v1/generate-quiz') return json(await generateQuiz(body, env));
      if (url.pathname === '/v1/regenerate-question') return json(await regenerateQuestion(body, env));
      if (url.pathname === '/v1/suggest-criteria') return json(await suggestCriteria(body, env));
      return json({ error: 'مسار غير معروف.' }, 404);
    } catch (e) {
      return json({ error: e.message || 'خطأ داخلي في الخادم.' }, e.status || 500);
    }
  },
};

function checkToken(token, env) {
  const list = String(env.ACCESS_TOKENS || '')
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => (t.includes(':') ? t.split(':').slice(1).join(':') : t));
  return token.length >= 8 && list.includes(token);
}

function json(obj, status = 200) {
  return cors(new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json; charset=utf-8' } }));
}

function cors(res) {
  res.headers.set('Access-Control-Allow-Origin', '*');
  res.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-Access-Token');
  return res;
}

function httpError(message, status = 400) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function validatePdf(body) {
  const pdf = body.pdf_base64;
  if (typeof pdf !== 'string' || pdf.length < 100) throw httpError('ملف القصة غير موجود.');
  if (pdf.length > MAX_PDF_BASE64) throw httpError('ملف القصة كبير جدًا.');
  return pdf;
}

async function callClaude(env, content, maxTokens = 6000) {
  if (!env.ANTHROPIC_API_KEY) throw httpError('الخادم غير مُعدّ (المفتاح غير موجود).', 500);
  const res = await fetch(ANTHROPIC_URL, {
    method: 'POST',
    headers: {
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: env.MODEL || DEFAULT_MODEL,
      max_tokens: maxTokens,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content }],
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    console.log('Claude API error', res.status, t.slice(0, 500));
    if (res.status === 429) throw httpError('الخدمة مشغولة حاليًا. أعد المحاولة بعد قليل.', 503);
    throw httpError('تعذر توليد الأسئلة حاليًا (خطأ من خدمة الذكاء الاصطناعي).', 502);
  }
  const data = await res.json();
  // قد يبدأ الرد بكتلة تفكير: نقرأ كتل النص فقط
  const text = (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  return extractJson(text);
}

function extractJson(text) {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.search(/[\[{]/);
  const endObj = t.lastIndexOf('}');
  const endArr = t.lastIndexOf(']');
  const end = Math.max(endObj, endArr);
  if (start < 0 || end < start) throw httpError('رد غير مفهوم من الذكاء الاصطناعي.', 502);
  try {
    return JSON.parse(t.slice(start, end + 1));
  } catch (_) {
    throw httpError('رد غير مفهوم من الذكاء الاصطناعي.', 502);
  }
}

function docBlock(pdf, title) {
  return { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdf }, title: String(title || 'القصة').slice(0, 200) };
}

function cleanQuestion(q, allowed) {
  if (!q || typeof q !== 'object') return null;
  const type = Object.keys(TYPE_NAMES).includes(q.type) ? q.type : 'single';
  if (allowed && allowed.length && !allowed.includes(type)) return null;
  const prompt = String(q.prompt || '').trim();
  if (!prompt) return null;
  let options = Array.isArray(q.options)
    ? q.options.map((o) => (typeof o === 'object' && o ? { label: String(o.label || '').trim(), correct: o.correct === true } : { label: String(o), correct: false }))
    : [];
  options = options.filter((o) => o.label);
  if (type === 'short') options = [];
  if (['single', 'complete', 'image', 'truefalse'].includes(type)) {
    if (options.length < 2 || options.filter((o) => o.correct).length !== 1) return null;
  }
  if (type === 'multi' && (options.length < 2 || !options.some((o) => o.correct))) return null;
  if (type === 'order') {
    if (options.length < 2) return null;
    options = options.map((o) => ({ label: o.label, correct: false }));
  }
  const d = Number(q.difficulty);
  return {
    type,
    prompt,
    options,
    keywords: Array.isArray(q.keywords) ? q.keywords.map(String).slice(0, 10) : [],
    image_hint: type === 'image' ? String(q.image_hint || '') : '',
    difficulty: d >= 1 && d <= 3 ? Math.round(d) : 2,
    skill: String(q.skill || ''),
    source_ref: String(q.source_ref || '').slice(0, 200),
  };
}

async function generateQuiz(body, env) {
  const pdf = validatePdf(body);
  const level = Math.min(6, Math.max(1, Number(body.level) || 3));
  const count = Math.min(15, Math.max(3, Number(body.count) || 6));
  const difficulty = Math.min(3, Math.max(1, Number(body.difficulty) || 2));
  const types = (Array.isArray(body.types) ? body.types : []).filter((t) => TYPE_NAMES[t]);
  const useTypes = types.length ? types : ['single', 'truefalse', 'order'];
  const instructions = `أعدّ ${count} أسئلة لتقييم فهم قصة «${body.title || ''}» (لغة القصة: ${body.language === 'fr' ? 'الفرنسية' : 'العربية'}).
${LEVEL_GUIDE[level]}
مستوى الصعوبة المطلوب: ${['', 'سهل', 'متوسط', 'صعب'][difficulty]}.
الأنواع المسموح بها (وزّع الأسئلة بينها بشكل متوازن):
${useTypes.map((t) => `- ${t}: ${TYPE_NAMES[t]}`).join('\n')}
${QUESTION_SCHEMA}
أعد كائن JSON: {"questions": [ ... ]}`;
  const out = await callClaude(env, [docBlock(pdf, body.title), { type: 'text', text: instructions }], 8000);
  const list = (Array.isArray(out) ? out : out.questions || []).map((q) => cleanQuestion(q, useTypes)).filter(Boolean);
  if (!list.length) throw httpError('لم تُنتج الخدمة أسئلة صالحة. أعد المحاولة.', 502);
  return { questions: list.slice(0, count) };
}

async function regenerateQuestion(body, env) {
  const pdf = validatePdf(body);
  const level = Math.min(6, Math.max(1, Number(body.level) || 3));
  const type = TYPE_NAMES[body.type] ? body.type : 'single';
  const avoid = (Array.isArray(body.avoid) ? body.avoid : []).map(String).slice(0, 30);
  const instructions = `أعدّ سؤالًا واحدًا جديدًا من نوع ${type} (${TYPE_NAMES[type]}) عن قصة «${body.title || ''}».
${LEVEL_GUIDE[level]}
الصعوبة: ${['', 'سهل', 'متوسط', 'صعب'][Math.min(3, Math.max(1, Number(body.difficulty) || 2))]}.
يجب أن يختلف عن هذه الأسئلة الموجودة:
${avoid.map((a) => `- ${a}`).join('\n')}
${QUESTION_SCHEMA}
أعد كائن JSON: {"question": { ... }}`;
  const out = await callClaude(env, [docBlock(pdf, body.title), { type: 'text', text: instructions }], 2500);
  const q = cleanQuestion(out.question || out, [type]);
  if (!q) throw httpError('لم تُنتج الخدمة سؤالًا صالحًا. أعد المحاولة.', 502);
  return { question: q };
}

async function suggestCriteria(body, env) {
  const stats = body.stats && typeof body.stats === 'object' ? body.stats : {};
  const instructions = `اقترح معايير لترتيب «أفضل قارئ» شهريًا وسنويًا في مدرسة ابتدائية، بهدف تحفيز قراءة القصص الورقية بإنصاف.
إحصائيات مجهولة (دون أي معلومة شخصية): ${JSON.stringify(stats).slice(0, 2000)}
أعد JSON فقط:
{"config": {"minStoriesMonthly": int, "minStoriesAnnual": int, "passPercent": int, "targetStoriesMonthly": int, "targetStoriesAnnual": int, "wComprehension": int, "wStories": int, "wRegularity": int},
 "rationale": "تعليل مختصر بالعربية في 3 جمل على الأكثر"}
الأوزان بين 0 و 100. راعِ أن الفهم أهم من الكم، وأن الشرط يجب أن يكون واقعيًا لعدد القصص المتوفرة.`;
  const out = await callClaude(env, [{ type: 'text', text: instructions }], 1200);
  return { config: out.config || {}, rationale: String(out.rationale || '') };
}
