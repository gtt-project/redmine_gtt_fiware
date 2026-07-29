// Row pickers: add (including with zero rows, #105), remove (including the
// last row), for both the entity and the attachment picker.

import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildForm, entityRow, initForm, loadScript } from './support/form_fixture.js';

beforeAll(loadScript);

describe('entity rows', () => {
  beforeEach(() => {
    buildForm({ entities: [{ type: 'WasteContainer', kind: 'idPattern', value: '.*' }] });
    initForm();
  });

  it('adds a row from the prototype', () => {
    document.getElementById('gtt-fiware-entity-add').click();
    const rows = document.querySelectorAll('#gtt-fiware-entity-rows .gtt-fiware-entity-row');
    expect(rows).toHaveLength(2);
    expect(rows[1].querySelector('.js-entity-type').value).toBe('');
    expect(rows[1].querySelector('.js-entity-match-value').value).toBe('.*');
  });

  it('removes a row', () => {
    document.querySelector('.js-entity-remove').click();
    expect(document.querySelectorAll('#gtt-fiware-entity-rows .gtt-fiware-entity-row')).toHaveLength(0);
  });

  it('adds again after every row was removed (#105)', () => {
    document.querySelector('.js-entity-remove').click();
    document.getElementById('gtt-fiware-entity-add').click();
    expect(document.querySelectorAll('#gtt-fiware-entity-rows .gtt-fiware-entity-row')).toHaveLength(1);
  });

  it('inserts new rows before the add link', () => {
    document.getElementById('gtt-fiware-entity-add').click();
    const container = document.getElementById('gtt-fiware-entity-rows');
    const children = Array.from(container.children);
    const addIndex = children.indexOf(document.getElementById('gtt-fiware-entity-add'));
    const lastRowIndex = children.lastIndexOf(children.filter(c => c.classList.contains('gtt-fiware-entity-row')).pop());
    expect(lastRowIndex).toBeLessThan(addIndex);
  });
});

describe('attachment rows', () => {
  beforeEach(() => {
    buildForm({ attachments: [{ url: 'https://example.com/a.jpg' }] });
    initForm();
  });

  it('adds a row from the prototype', () => {
    document.getElementById('gtt-fiware-attachment-add').click();
    expect(document.querySelectorAll('#gtt-fiware-attachment-rows .gtt-fiware-attachment-row')).toHaveLength(2);
  });

  it('removes the last row and can add again (#104)', () => {
    document.querySelector('.js-attachment-remove').click();
    expect(document.querySelectorAll('#gtt-fiware-attachment-rows .gtt-fiware-attachment-row')).toHaveLength(0);
    document.getElementById('gtt-fiware-attachment-add').click();
    expect(document.querySelectorAll('#gtt-fiware-attachment-rows .gtt-fiware-attachment-row')).toHaveLength(1);
  });
});
