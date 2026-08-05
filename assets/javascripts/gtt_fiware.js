/* Shared page helpers, loaded on every page via the layout hook.
 *
 * showNotification is a deliberate global: the publish/unpublish/copy/sync
 * js.erb responses and the subscription list call it by name. It writes to
 * the #temporaryNotification box the list view renders; on pages without
 * that box the call is a no-op rather than a TypeError.
 */
(function() {
  'use strict';

  window.showNotification = function(message) {
    var notification = document.getElementById('temporaryNotification');
    if (!notification) { return; }

    notification.textContent = message;
    notification.classList.add('visible');
    setTimeout(function() {
      notification.classList.remove('visible');
    }, 3000);
  };
})();
