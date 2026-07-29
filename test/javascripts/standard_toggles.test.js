// Standard-aware behaviour (#66): the selected connection decides NGSIv2 vs
// NGSI-LD, and the form adapts - field visibility, alteration-type labels
// and the LD entityUpdated fold, the oneshot status option, and the
// create-and-publish button.

import { beforeAll, describe, expect, it } from 'vitest';
import { buildForm, initForm, loadScript, selectConnection } from './support/form_fixture.js';

beforeAll(loadScript);

const qs = (sel) => document.querySelector(sel);

describe('field visibility', () => {
  it('hides v2-only and shows LD-only elements for an LD connection', () => {
    buildForm({ standard: 'NGSI-LD' });
    initForm();
    expect(qs('.js-ngsi-v2-only').style.display).toBe('none');
    expect(qs('.js-ngsi-ld-only').style.display).toBe('');
  });

  it('shows v2-only and hides LD-only elements for an NGSIv2 connection', () => {
    buildForm({ standard: 'NGSIv2' });
    initForm();
    expect(qs('.js-ngsi-v2-only').style.display).toBe('');
    expect(qs('.js-ngsi-ld-only').style.display).toBe('none');
  });

  it('treats an unknown standard (no connection picked) as NGSIv2 layout', () => {
    buildForm({ connectionSelected: false });
    initForm();
    expect(qs('.js-ngsi-v2-only').style.display).toBe('');
    expect(qs('.js-ngsi-ld-only').style.display).toBe('none');
  });
});

describe('alteration types', () => {
  it('swaps labels to NGSI-LD trigger names for an LD connection', () => {
    buildForm({ standard: 'NGSI-LD' });
    initForm();
    const labels = Array.from(document.querySelectorAll('.js-alteration-label')).map(c => c.textContent);
    expect(labels).toEqual(['entityCreated', 'entityUpdated', 'entityUpdated', 'entityDeleted']);
  });

  it('hides the redundant entityUpdate choice for LD and keeps it for v2', () => {
    buildForm({ standard: 'NGSI-LD' });
    initForm();
    expect(qs('.js-alteration-choice[data-type="entityUpdate"]').style.display).toBe('none');

    buildForm({ standard: 'NGSIv2' });
    initForm();
    expect(qs('.js-alteration-choice[data-type="entityUpdate"]').style.display).toBe('');
  });

  it('folds a checked entityUpdate into entityChange when switching to LD', () => {
    buildForm({ standard: 'NGSIv2', alterationChecked: ['entityUpdate'] });
    initForm();
    selectConnection('1'); // still v2: nothing folds
    expect(qs('.js-alteration-choice[data-type="entityUpdate"] input').checked).toBe(true);

    buildForm({ standard: 'NGSI-LD', alterationChecked: ['entityUpdate'] });
    initForm();
    expect(qs('.js-alteration-choice[data-type="entityUpdate"] input').checked).toBe(false);
    expect(qs('.js-alteration-choice[data-type="entityChange"] input').checked).toBe(true);
  });
});

describe('oneshot status', () => {
  it('hides and disables oneshot for LD, reselecting active when it was chosen', () => {
    buildForm({ standard: 'NGSI-LD', status: 'oneshot' });
    initForm();
    const select = document.getElementById('gtt-fiware-status-select');
    const oneshot = select.querySelector('option[value="oneshot"]');
    expect(oneshot.disabled).toBe(true);
    expect(oneshot.hidden).toBe(true);
    expect(select.value).toBe('active');
  });

  it('keeps oneshot selectable for NGSIv2', () => {
    buildForm({ standard: 'NGSIv2', status: 'oneshot' });
    initForm();
    const select = document.getElementById('gtt-fiware-status-select');
    expect(select.querySelector('option[value="oneshot"]').disabled).toBe(false);
    expect(select.value).toBe('oneshot');
  });
});

describe('create-and-publish button', () => {
  it('is visible only for stored-token connections', () => {
    buildForm({ authMode: 'stored' });
    initForm();
    expect(qs('input[name="publish_after_create"]').style.display).toBe('');

    buildForm({ authMode: 'proxied' });
    initForm();
    expect(qs('input[name="publish_after_create"]').style.display).toBe('none');
  });

  it('reacts to changing the selected connection', () => {
    buildForm({ standard: 'NGSIv2', connectionSelected: false });
    initForm();
    expect(qs('.js-ngsi-v2-only').style.display).toBe('');
    selectConnection('1');
    expect(qs('input[name="publish_after_create"]').style.display).toBe('');
  });
});
