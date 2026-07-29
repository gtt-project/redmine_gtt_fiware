/* Guided subscription creation (#102): a presentation layer over the single
 * form. Form elements and sections carry data-wizard-step (1..4); the wizard
 * shows one step at a time with Back/Next, validates the visible required
 * fields before advancing, and offers a "show all fields" escape hatch that
 * returns to the classic full form. State always lives in the one form, so
 * nothing is lost when stepping around or leaving the wizard.
 *
 * Activates only on forms marked data-wizard (the new-template page). With
 * the script absent or JavaScript off, the classic form renders unchanged.
 */
(function() {
  'use strict';

  var TOTAL_STEPS = 4;

  function init() {
    var form = document.querySelector('form[data-wizard]');
    var nav = document.getElementById('gtt-fiware-wizard');
    var buttons = document.getElementById('gtt-fiware-wizard-buttons');
    if (!form || !nav || !buttons) { return; }
    if (form.dataset.gttFiwareWizardInit) { return; }
    form.dataset.gttFiwareWizardInit = '1';

    var back = document.getElementById('gtt-fiware-wizard-back');
    var next = document.getElementById('gtt-fiware-wizard-next');
    var showAll = document.getElementById('gtt-fiware-wizard-all');
    var help = document.getElementById('gtt-fiware-wizard-help');
    var current = 1;

    function stepped() {
      return form.querySelectorAll('[data-wizard-step]');
    }

    // Sections are the collapsible fieldsets from the classic form; a step
    // that contains one gets it expanded, nothing stays behind a fold.
    // Expansion goes through Redmine's own toggleFieldset so the legend icon
    // stays in sync; the manual fallback covers environments without it.
    function expandSection(el) {
      if (!el.classList.contains('collapsible') || !el.classList.contains('collapsed')) { return; }
      var legend = el.querySelector(':scope > legend');
      if (typeof window.toggleFieldset === 'function' && legend) {
        window.toggleFieldset(legend);
        return;
      }
      el.classList.remove('collapsed');
      var body = el.querySelector(':scope > div');
      if (body) { body.style.display = ''; }
    }

    function showStep(step) {
      current = step;
      stepped().forEach(function(el) {
        var active = Number(el.dataset.wizardStep) === step;
        el.style.display = active ? '' : 'none';
        if (active) { expandSection(el); }
      });
      nav.querySelectorAll('li').forEach(function(li) {
        li.classList.toggle('active', Number(li.dataset.step) === step);
      });
      var activeItem = nav.querySelector('li[data-step="' + step + '"]');
      help.textContent = activeItem ? activeItem.dataset.help : '';
      back.disabled = step === 1;
      next.style.display = step === TOTAL_STEPS ? 'none' : '';
      // The preview result manages its own visibility (the preview button
      // shows it); the wizard only makes sure it never lingers on steps
      // before Review & publish.
      var previewResult = document.getElementById('gtt-fiware-preview-result');
      if (previewResult && step !== TOTAL_STEPS) { previewResult.style.display = 'none'; }
    }

    // Required fields of the current step must hold before advancing;
    // otherwise the browser would refuse to submit while the invalid field
    // is hidden on an earlier step, with no visible feedback.
    function currentStepValid() {
      var selector = '[data-wizard-step="' + current + '"] input[required], ' +
                     '[data-wizard-step="' + current + '"] select[required], ' +
                     '[data-wizard-step="' + current + '"] textarea[required]';
      var fields = form.querySelectorAll(selector);
      for (var i = 0; i < fields.length; i++) {
        if (!fields[i].checkValidity()) {
          if (fields[i].reportValidity) { fields[i].reportValidity(); }
          return false;
        }
      }
      return true;
    }

    function teardown() {
      nav.style.display = 'none';
      buttons.style.display = 'none';
      stepped().forEach(function(el) {
        el.style.display = '';
      });
    }

    back.addEventListener('click', function() {
      if (current > 1) { showStep(current - 1); }
    });
    next.addEventListener('click', function() {
      if (current < TOTAL_STEPS && currentStepValid()) { showStep(current + 1); }
    });
    showAll.addEventListener('click', function(e) {
      e.preventDefault();
      teardown();
    });

    nav.style.display = '';
    buttons.style.display = '';
    showStep(1);
  }

  window.GttFiwareWizard = { init: init };
  document.addEventListener('DOMContentLoaded', init);
})();
