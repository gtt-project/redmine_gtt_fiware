// The "Edit as JSON" toggle: switching serializes the rows into the JSON
// field, hides the rows, and switching back restores the picker.

import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildForm, initForm, loadScript } from './support/form_fixture.js';

beforeAll(loadScript);

const toggle = (target) => document.querySelector(`.js-json-toggle[data-target="${target}"]`).click();

describe('entities JSON mode', () => {
  beforeEach(() => {
    buildForm({ entities: [{ type: 'WasteContainer', kind: 'idPattern', value: '.*' }] });
    initForm();
  });

  it('serializes current rows into the JSON field on switch', () => {
    toggle('entities');
    expect(JSON.parse(document.getElementById('subscription_template_entities_string').value))
      .toEqual([{ type: 'WasteContainer', idPattern: '.*' }]);
  });

  it('shows the JSON field and hides the rows, then round-trips back', () => {
    const rows = document.getElementById('gtt-fiware-entity-rows');
    const json = document.getElementById('gtt-fiware-entities-json');

    toggle('entities');
    expect(json.classList.contains('hidden')).toBe(false);
    expect(rows.style.display).toBe('none');

    toggle('entities');
    expect(json.classList.contains('hidden')).toBe(true);
    expect(rows.style.display).toBe('');
  });

  it('does not overwrite hand-edited JSON when toggling back and forth', () => {
    toggle('entities');
    const field = document.getElementById('subscription_template_entities_string');
    field.value = '[{"type":"HandEdited"}]';
    toggle('entities'); // back to rows: serialize skips, JSON mode was on
    expect(field.value).toBe('[{"type":"HandEdited"}]');
  });
});

describe('attachments JSON mode', () => {
  it('serializes rows into the JSON field on switch', () => {
    buildForm({ attachments: [{ url: 'https://example.com/a.jpg' }] });
    initForm();
    toggle('attachments');
    expect(JSON.parse(document.getElementById('subscription_template_attachments_string').value))
      .toEqual([{ url: 'https://example.com/a.jpg' }]);
  });
});
