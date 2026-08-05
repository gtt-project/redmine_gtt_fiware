// The live template preview (#68): the button POSTs the current template
// fields and renders the response into #gtt-fiware-preview-result. The
// response is untrusted broker data, so rendering must go through
// textContent, and only the latest request may write the result box.

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildForm, initForm, loadScript } from './support/form_fixture.js';

beforeAll(loadScript);

// A controllable fetch: each call returns a promise the test resolves by
// hand, so response order is scriptable.
function stubFetch() {
  const calls = [];
  vi.stubGlobal('fetch', (url, options) => new Promise((resolve, reject) => {
    calls.push({
      url,
      options,
      respond(json, ok = true) {
        resolve({ ok, json: () => Promise.resolve(json) });
      },
      fail() {
        reject(new Error('network down'));
      }
    });
  }));
  return calls;
}

const clickPreview = () => document.getElementById('gtt-fiware-preview-button').click();
const resultBox = () => document.getElementById('gtt-fiware-preview-result');
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('live preview', () => {
  let calls;

  beforeEach(() => {
    buildForm({ entities: [{ type: 'TemperatureSensor', kind: 'idPattern', value: '.*' }] });
    initForm();
    calls = stubFetch();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('sends the template fields and the CSRF token', () => {
    clickPreview();
    expect(calls).toHaveLength(1);
    expect(calls[0].options.headers['X-CSRF-Token']).toBe('test-csrf');
    const body = JSON.parse(calls[0].options.body);
    expect(body.entity_type).toBe('TemperatureSensor');
    expect(body.subject).toBe('${type} ${id}');
  });

  it('renders the rendered fields as text, never as HTML', async () => {
    clickPreview();
    calls[0].respond({
      entity_id: 'urn:x:1',
      subject: '<img src=x onerror=alert(1)>',
      description: 'Temperature is 30',
      notes: null,
      has_geometry: true
    });
    await flush();
    const box = resultBox();
    expect(box.querySelector('img')).toBeNull();
    expect(box.textContent).toContain('<img src=x onerror=alert(1)>');
    expect(box.textContent).toContain('Rendered against urn:x:1, geometry included');
  });

  it('shows the server error message on a failed response', async () => {
    clickPreview();
    calls[0].respond({ error: 'No entity of that type' }, false);
    await flush();
    expect(resultBox().textContent).toBe('No entity of that type');
  });

  it('shows the generic error on a network failure', async () => {
    clickPreview();
    calls[0].fail();
    await flush();
    expect(resultBox().textContent).toBe('Preview failed');
  });

  // Two clicks, first response arriving last: the stale response must not
  // overwrite the newer one.
  it('ignores out-of-order responses', async () => {
    clickPreview();
    clickPreview();
    expect(calls).toHaveLength(2);
    calls[1].respond({ entity_id: 'urn:new', subject: 'newer', description: null, notes: null, has_geometry: false });
    await flush();
    calls[0].respond({ entity_id: 'urn:old', subject: 'older', description: null, notes: null, has_geometry: false });
    await flush();
    expect(resultBox().textContent).toContain('newer');
    expect(resultBox().textContent).not.toContain('older');
  });
});
