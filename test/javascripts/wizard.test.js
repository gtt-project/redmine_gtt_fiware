// Guided subscription creation (#102): stepping, validation gating, the
// escape hatch, and section auto-expansion. The fixture mirrors the wizard
// DOM contract of new.html.erb and the data-wizard-step tagging.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, '../../assets/javascripts/gtt_fiware_wizard.js'), 'utf8');

beforeAll(() => window.eval(source));

function buildWizardForm({ wizard = true, nameValue = 'My subscription' } = {}) {
  document.body.innerHTML = `
    <form ${wizard ? 'data-wizard="true"' : ''}>
      <div id="gtt-fiware-wizard" style="display: none;">
        <ol class="gtt-fiware-wizard-steps">
          <li data-step="1" data-help="Help one">Connection</li>
          <li data-step="2" data-help="Help two">What to watch</li>
          <li data-step="3" data-help="Help three">The issue</li>
          <li data-step="4" data-help="Help four">Review &amp; publish</li>
        </ol>
        <p class="gtt-fiware-wizard-help"><em id="gtt-fiware-wizard-help"></em></p>
      </div>

      <p data-wizard-step="1"><input type="text" id="name" required value="${nameValue}" /></p>
      <fieldset class="collapsible collapsed" data-wizard-step="2" id="section-filters">
        <legend>Filters</legend>
        <div style="display: none;"><input type="text" id="query" /></div>
      </fieldset>
      <p data-wizard-step="3"><input type="text" id="subject" required value="A subject" /></p>
      <p data-wizard-step="4"><input type="submit" value="Create" /></p>

      <p id="gtt-fiware-wizard-buttons" style="display: none;">
        <button type="button" id="gtt-fiware-wizard-back">Back</button>
        <button type="button" id="gtt-fiware-wizard-next">Next</button>
        <a href="#" id="gtt-fiware-wizard-all">Show all fields</a>
      </p>
    </form>`;
  window.GttFiwareWizard.init();
}

const visible = (sel) => document.querySelector(sel).style.display !== 'none';
const next = () => document.getElementById('gtt-fiware-wizard-next').click();
const back = () => document.getElementById('gtt-fiware-wizard-back').click();

describe('activation', () => {
  it('shows only step 1 and the nav on a wizard form', () => {
    buildWizardForm();
    expect(visible('#gtt-fiware-wizard')).toBe(true);
    expect(visible('#gtt-fiware-wizard-buttons')).toBe(true);
    expect(visible('[data-wizard-step="1"]')).toBe(true);
    expect(visible('[data-wizard-step="2"]')).toBe(false);
    expect(visible('[data-wizard-step="4"]')).toBe(false);
    expect(document.getElementById('gtt-fiware-wizard-help').textContent).toBe('Help one');
  });

  it('stays inert without data-wizard (the edit form)', () => {
    buildWizardForm({ wizard: false });
    expect(visible('#gtt-fiware-wizard')).toBe(false);
    expect(visible('[data-wizard-step="2"]')).toBe(true);
  });
});

describe('stepping', () => {
  beforeEach(() => buildWizardForm());

  it('advances and goes back, tracking the active item and help text', () => {
    next();
    expect(visible('[data-wizard-step="2"]')).toBe(true);
    expect(visible('[data-wizard-step="1"]')).toBe(false);
    expect(document.querySelector('li.active').dataset.step).toBe('2');
    expect(document.getElementById('gtt-fiware-wizard-help').textContent).toBe('Help two');
    back();
    expect(visible('[data-wizard-step="1"]')).toBe(true);
  });

  it('disables Back on step 1 and hides Next on the last step', () => {
    expect(document.getElementById('gtt-fiware-wizard-back').disabled).toBe(true);
    next(); next(); next();
    expect(document.querySelector('li.active').dataset.step).toBe('4');
    expect(visible('#gtt-fiware-wizard-next')).toBe(false);
    expect(visible('[data-wizard-step="4"]')).toBe(true);
  });

  it('expands a collapsed section when its step activates', () => {
    next();
    const section = document.getElementById('section-filters');
    expect(section.classList.contains('collapsed')).toBe(false);
    expect(section.querySelector('div').style.display).toBe('');
  });
});

describe('validation gate', () => {
  it('does not advance while a required field of the step is empty', () => {
    buildWizardForm({ nameValue: '' });
    next();
    expect(document.querySelector('li.active').dataset.step).toBe('1');
    expect(visible('[data-wizard-step="1"]')).toBe(true);
  });
});

describe('escape hatch', () => {
  it('shows the whole form and hides the wizard chrome', () => {
    buildWizardForm();
    document.getElementById('gtt-fiware-wizard-all').click();
    expect(visible('#gtt-fiware-wizard')).toBe(false);
    expect(visible('#gtt-fiware-wizard-buttons')).toBe(false);
    ['1', '2', '3', '4'].forEach((step) => {
      expect(visible(`[data-wizard-step="${step}"]`)).toBe(true);
    });
  });
});
