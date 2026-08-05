// The "Edit as JSON" toggle: switching serializes the rows into the JSON
// field, hides the rows, and switching back restores the picker.

import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildForm, initForm, loadScript, submitForm } from './support/form_fixture.js';

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

  it('rebuilds the rows from hand-edited JSON when toggling back', () => {
    toggle('entities');
    const field = document.getElementById('subscription_template_entities_string');
    field.value = '[{"type":"HandEdited","id":"urn:x:1"}]';
    toggle('entities');
    const row = document.querySelector('.gtt-fiware-entity-row');
    expect(row.querySelector('.js-entity-type').value).toBe('HandEdited');
    expect(row.querySelector('.js-entity-match-kind').value).toBe('id');
    expect(row.querySelector('.js-entity-match-value').value).toBe('urn:x:1');
  });

  // The regression this pins: the field used to survive the toggle-back
  // only until submit, when the stale rows overwrote it.
  it('keeps hand-edited JSON through toggle-back and submit', () => {
    toggle('entities');
    const field = document.getElementById('subscription_template_entities_string');
    field.value = '[{"type":"HandEdited"}]';
    toggle('entities');
    submitForm();
    expect(JSON.parse(field.value)).toEqual([{ type: 'HandEdited' }]);
  });

  // JSON the picker cannot show (extra members) must never be replaced by
  // stale rows: the form refuses to leave JSON mode.
  it('stays in JSON mode when the JSON is not representable by the picker', () => {
    toggle('entities');
    const field = document.getElementById('subscription_template_entities_string');
    field.value = '[{"type":"Sensor","id":"urn:x:1","extra":"member"}]';
    toggle('entities');
    const json = document.getElementById('gtt-fiware-entities-json');
    expect(json.classList.contains('hidden')).toBe(false);
    submitForm();
    expect(field.value).toBe('[{"type":"Sensor","id":"urn:x:1","extra":"member"}]');
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
