/* Subscription template list behaviour (#145): the rails-ujs handlers for
 * the row action links (publish, unpublish, sync, copy), previously an
 * inline script in _list.html.erb.
 *
 * Two response kinds arrive here:
 *   - server-side publish/unpublish answer with re-rendered rows (text/html)
 *     and the outcome message in the X-Redmine-Message header; the list is
 *     swapped and the message shown,
 *   - sync, copy and browser-mode publish/unpublish answer with JS
 *     (text/javascript) that rails-ujs executes and that updates the page
 *     itself; the list must NOT be overwritten with the script source.
 *
 * The broker token header is only attached when the token box exists, i.e.
 * when some connection on the page authenticates from the browser (#95).
 *
 * Exposes window.GttFiwareList.init for the tests.
 */
(function() {
  'use strict';

  function init() {
    var list = document.getElementById('subscriptionTemplateList');
    if (!list) { return; }

    document.addEventListener('ajax:beforeSend', function(event) {
      var tokenInput = document.getElementById('subscription_auth_token');
      if (!tokenInput) { return; }
      var xhr = event.detail[0];
      xhr.setRequestHeader('FIWARE-Broker-Auth-Token', tokenInput.value);
    });

    document.addEventListener('ajax:success', function(event) {
      var xhr = event.detail[2];
      var contentType = xhr.getResponseHeader('Content-Type') || '';
      if (contentType.indexOf('text/html') !== -1) {
        list.innerHTML = xhr.responseText;
      }
      notifyFromHeader(xhr);
    });

    document.addEventListener('ajax:error', function(event) {
      var xhr = event.detail[2];
      notifyFromHeader(xhr);
    });
  }

  function notifyFromHeader(xhr) {
    var message = xhr.getResponseHeader('X-Redmine-Message');
    if (message) { window.showNotification(message); }
  }

  window.GttFiwareList = { init: init };
  document.addEventListener('DOMContentLoaded', init);
})();
