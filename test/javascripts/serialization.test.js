// Submit-time serialization of the pickers into the *_string / attrs fields.

import { beforeAll, describe, expect, it } from 'vitest';
import { buildForm, initForm, loadScript, submitForm } from './support/form_fixture.js';

beforeAll(loadScript);

const field = (id) => document.getElementById(id);

describe('entities', () => {
  it('serializes type with the selected match kind', () => {
    buildForm({ entities: [{ type: 'WasteContainer', kind: 'idPattern', value: 'urn:.*' }] });
    initForm();
    submitForm();
    expect(JSON.parse(field('subscription_template_entities_string').value))
      .toEqual([{ type: 'WasteContainer', idPattern: 'urn:.*' }]);
  });

  it('serializes an exact id match', () => {
    buildForm({ entities: [{ type: 'Room', kind: 'id', value: 'urn:ngsi-ld:Room:1' }] });
    initForm();
    submitForm();
    expect(JSON.parse(field('subscription_template_entities_string').value))
      .toEqual([{ type: 'Room', id: 'urn:ngsi-ld:Room:1' }]);
  });

  it('omits the match key when the value is blank and skips typeless rows', () => {
    buildForm({
      entities: [
        { type: 'Room', kind: 'idPattern', value: '' },
        { type: '', kind: 'idPattern', value: '.*' }
      ]
    });
    initForm();
    submitForm();
    expect(JSON.parse(field('subscription_template_entities_string').value)).toEqual([{ type: 'Room' }]);
  });

  it('clears the field when no row has a type', () => {
    buildForm({ entities: [{ type: '', kind: 'idPattern', value: '.*' }] });
    initForm();
    submitForm();
    expect(field('subscription_template_entities_string').value).toBe('');
  });

  it('leaves the JSON field alone while JSON mode is active', () => {
    buildForm({ entities: [{ type: 'Room', kind: 'idPattern', value: '.*' }], entitiesJsonMode: true });
    initForm();
    field('subscription_template_entities_string').value = '[{"type":"HandEdited"}]';
    submitForm();
    expect(field('subscription_template_entities_string').value).toBe('[{"type":"HandEdited"}]');
  });
});

describe('watched attributes', () => {
  it('turns the comma list into a JSON array, trimming blanks', () => {
    buildForm({ attrs: ' temperature, fillingLevel ,, ' });
    initForm();
    submitForm();
    expect(JSON.parse(field('subscription_template_attrs').value)).toEqual(['temperature', 'fillingLevel']);
  });

  it('clears the field for an empty list', () => {
    buildForm({ attrs: '  ' });
    initForm();
    submitForm();
    expect(field('subscription_template_attrs').value).toBe('');
  });
});

describe('issue geometry', () => {
  it('location mode writes the ${location} placeholder', () => {
    buildForm({ geometryMode: 'location' });
    initForm();
    submitForm();
    expect(field('subscription_template_geometry_string').value).toBe('"${location}"');
  });

  it('none mode writes the literal null that clears a stored geometry', () => {
    buildForm({ geometryMode: 'none' });
    initForm();
    submitForm();
    expect(field('subscription_template_geometry_string').value).toBe('null');
  });

  it('custom mode passes the textarea through untouched', () => {
    buildForm({ geometryMode: 'custom' });
    initForm();
    field('subscription_template_geometry_string').value = '{"type":"Feature"}';
    submitForm();
    expect(field('subscription_template_geometry_string').value).toBe('{"type":"Feature"}');
  });
});

describe('attachments', () => {
  it('serializes url with optional filename and description', () => {
    buildForm({
      attachments: [
        { url: 'https://example.com/a.jpg', filename: 'photo-${id}.jpg', description: 'Photo' },
        { url: 'https://example.com/b.jpg' }
      ]
    });
    initForm();
    submitForm();
    expect(JSON.parse(field('subscription_template_attachments_string').value)).toEqual([
      { url: 'https://example.com/a.jpg', filename: 'photo-${id}.jpg', description: 'Photo' },
      { url: 'https://example.com/b.jpg' }
    ]);
  });

  it('writes the literal null that clears stored attachments when no row has a url', () => {
    buildForm({ attachments: [{ url: '', filename: 'x.jpg' }] });
    initForm();
    submitForm();
    expect(field('subscription_template_attachments_string').value).toBe('null');
  });
});

describe('geographic area', () => {
  it('anywhere clears the georel/geometry/coords triple', () => {
    buildForm({ geoMode: 'anywhere' });
    initForm();
    field('subscription_template_expression_georel').value = 'coveredBy';
    field('subscription_template_expression_geometry').value = 'polygon';
    field('subscription_template_expression_coords').value = '1,2;3,4';
    submitForm();
    expect(field('subscription_template_expression_georel').value).toBe('');
    expect(field('subscription_template_expression_geometry').value).toBe('');
    expect(field('subscription_template_expression_coords').value).toBe('');
  });

  it('boundary writes a coveredBy polygon in lat,lon order from the data-geom ring', () => {
    buildForm({ geoMode: 'boundary' });
    initForm();
    submitForm();
    expect(field('subscription_template_expression_georel').value).toBe('coveredBy');
    expect(field('subscription_template_expression_geometry').value).toBe('polygon');
    expect(field('subscription_template_expression_coords').value)
      .toBe('35.67,139.69;35.68,139.7;35.675,139.695;35.67,139.69');
  });

  // data-geom is server-rendered, but a malformed value must not throw from
  // inside the submit listener (the submit proceeds regardless), and must
  // leave the stored triple alone rather than half-writing it.
  it('boundary with a malformed data-geom leaves the triple untouched', () => {
    buildForm({ geoMode: 'boundary' });
    initForm();
    document.querySelector('input[value="boundary"]').dataset.geom = '{"geometry":{"coordinates":[]}}';
    field('subscription_template_expression_georel').value = 'kept';
    expect(() => submitForm()).not.toThrow();
    expect(field('subscription_template_expression_georel').value).toBe('kept');
    expect(field('subscription_template_expression_geometry').value).toBe('');
  });

  it('custom leaves the triple untouched', () => {
    buildForm({ geoMode: 'custom' });
    initForm();
    field('subscription_template_expression_georel').value = 'near;maxDistance:1000';
    field('subscription_template_expression_geometry').value = 'polygon';
    field('subscription_template_expression_coords').value = '9,9';
    submitForm();
    expect(field('subscription_template_expression_georel').value).toBe('near;maxDistance:1000');
    expect(field('subscription_template_expression_coords').value).toBe('9,9');
  });
});
