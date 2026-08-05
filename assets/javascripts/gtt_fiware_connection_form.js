/* Broker connection form behaviour (#145): shows only the fields that apply
 * to the selected standard, previously an inline script in
 * broker_connections/_form.html.erb.
 *
 * Same js-ngsi-v2-only / js-ngsi-ld-only convention as the template form
 * (gtt_fiware_form.js), keyed off the standard select instead of the
 * connection select. Hidden values are kept, not cleared, so switching the
 * standard back does not lose input.
 *
 * Exposes window.GttFiwareConnectionForm.init for the tests.
 */
(function() {
  'use strict';

  function init() {
    var standardSelect = document.getElementById('broker_connection_standard');
    if (!standardSelect) { return; }

    function applyStandard() {
      var isLd = standardSelect.value === 'NGSI-LD';
      document.querySelectorAll('.js-ngsi-v2-only').forEach(function(el) {
        el.style.display = isLd ? 'none' : '';
      });
      document.querySelectorAll('.js-ngsi-ld-only').forEach(function(el) {
        el.style.display = isLd ? '' : 'none';
      });
    }

    standardSelect.addEventListener('change', applyStandard);
    applyStandard();
  }

  window.GttFiwareConnectionForm = { init: init };
  document.addEventListener('DOMContentLoaded', init);
})();
