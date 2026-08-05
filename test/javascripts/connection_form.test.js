// The broker connection form (gtt_fiware_connection_form.js): fields that
// only apply to one standard follow the standard select, same
// js-ngsi-*-only convention as the template form.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));

beforeAll(() => {
  window.eval(readFileSync(
    join(here, '../../assets/javascripts/gtt_fiware_connection_form.js'), 'utf8'
  ));
});

function buildForm(standard) {
  document.body.innerHTML = `
    <select id="broker_connection_standard">
      <option value="NGSIv2" ${standard === 'NGSIv2' ? 'selected' : ''}>NGSIv2</option>
      <option value="NGSI-LD" ${standard === 'NGSI-LD' ? 'selected' : ''}>NGSI-LD</option>
    </select>
    <p class="js-ngsi-v2-only" id="servicepath"></p>
    <p class="js-ngsi-ld-only" id="context"></p>
    <div class="js-ngsi-ld-only" id="emission"></div>`;
  window.GttFiwareConnectionForm.init();
}

function displayOf(id) {
  return document.getElementById(id).style.display;
}

describe('broker connection standard toggle', () => {
  it('shows only the LD fields when NGSI-LD is selected', () => {
    buildForm('NGSI-LD');
    expect(displayOf('servicepath')).toBe('none');
    expect(displayOf('context')).toBe('');
    expect(displayOf('emission')).toBe('');
  });

  it('shows only the v2 fields when NGSIv2 is selected', () => {
    buildForm('NGSIv2');
    expect(displayOf('servicepath')).toBe('');
    expect(displayOf('context')).toBe('none');
    expect(displayOf('emission')).toBe('none');
  });

  it('follows a change of the select', () => {
    buildForm('NGSI-LD');
    const select = document.getElementById('broker_connection_standard');
    select.value = 'NGSIv2';
    select.dispatchEvent(new Event('change'));
    expect(displayOf('servicepath')).toBe('');
    expect(displayOf('emission')).toBe('none');
  });

  it('does nothing on pages without the select', () => {
    document.body.innerHTML = '<p class="js-ngsi-v2-only"></p>';
    expect(() => window.GttFiwareConnectionForm.init()).not.toThrow();
  });
});
