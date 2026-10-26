import assert from 'node:assert/strict';
import test from 'node:test';
import { ApiError } from '../http/errors.ts';
import { materialInput, teamPlanSchema, validateAnalysisFilename } from './team-analysis.ts';

test('AI materials preserve UTF-8 text and reject unsupported or binary-disguised files explicitly', () => {
  assert.deepEqual(materialInput('brief.md', Buffer.from('Zażółć gęślą jaźń')), [
    { type: 'input_text', text: 'Materiał projektu: "brief.md"' },
    { type: 'input_text', text: 'Zażółć gęślą jaźń' },
  ]);
  for (const filename of ['archive.zip', 'program.exe', '.env', 'animation.gif', 'unknown']) {
    assert.throws(() => validateAnalysisFilename(filename), (error: unknown) => error instanceof ApiError && error.code === 'AI_UNSUPPORTED_FILE');
  }
  for (const bytes of [Buffer.from([255, 255]), Buffer.from('text\0binary')]) {
    assert.throws(() => materialInput('brief.txt', bytes), (error: unknown) => error instanceof ApiError && error.code === 'AI_TEXT_ENCODING_INVALID');
  }
});

test('PDF, Office and image materials retain their exact bytes with explicit MIME types', () => {
  const pdf = Buffer.from('%PDF-1.7\nSynthetic fixture');
  const inputs = materialInput('brief.PDF', pdf);
  assert.deepEqual(inputs[1], {
    type: 'input_file', filename: 'brief.PDF', file_data: `data:application/pdf;base64,${pdf.toString('base64')}`,
  });
  assert.throws(() => materialInput('bad.pdf', Buffer.from('not a pdf')), /nagłówka PDF/);
  const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
  assert.deepEqual(materialInput('diagram.png', png)[1], {
    type: 'input_image', image_url: `data:image/png;base64,${png.toString('base64')}`, detail: 'auto',
  });
  assert.throws(() => materialInput('bad.png', pdf), /format obrazu/);
  assert.equal(materialInput('requirements.docx', Buffer.from('synthetic-office'))[1]?.type, 'input_file');
});

test('task plans require actual team bot IDs, valid priorities, bounded content and no extra fields', () => {
  const schema = teamPlanSchema(['team-bot']);
  const task = { botId: 'team-bot', title: 'Implement form', description: 'Include validation tests.', priority: 'HIGH' };
  assert.ok(schema.safeParse({ summary: 'Plan', tasks: [task] }).success);
  assert.ok(schema.safeParse({ summary: 'Already planned', tasks: [] }).success);
  for (const invalid of [
    { ...task, botId: 'another-team-bot' }, { ...task, priority: 'MAXIMUM' },
    { ...task, title: 'x'.repeat(201) }, { ...task, description: '' }, { ...task, command: 'run code' },
  ]) assert.equal(schema.safeParse({ summary: 'Plan', tasks: [invalid] }).success, false);
  assert.equal(schema.safeParse({ summary: 'Plan', tasks: Array(101).fill(task) }).success, false);
});
