// The subscription template list (gtt_fiware_list.js): rails-ujs response
// handling for the row action links.
//
// The contract under test: HTML responses (server-side publish/unpublish)
// replace the list rows and show the X-Redmine-Message outcome; JS responses
// (sync, copy, browser-mode publish/unpublish) are executed by rails-ujs and
// update the page themselves, so the handler must leave the list alone. The
// broker token request header is only attached while the token box exists.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));

beforeAll(() => {
  document.body.innerHTML = `
    <p class="min-width"><input type="text" id="subscription_auth_token" /></p>
    <table><tbody id="subscriptionTemplateList"><tr id="original"></tr></tbody></table>
    <div id="temporaryNotification"></div>`;
  window.eval(readFileSync(join(here, '../../assets/javascripts/gtt_fiware.js'), 'utf8'));
  window.eval(readFileSync(join(here, '../../assets/javascripts/gtt_fiware_list.js'), 'utf8'));
  window.GttFiwareList.init();
});

beforeEach(() => {
  document.getElementById('subscriptionTemplateList').innerHTML = '<tr id="original"></tr>';
  document.getElementById('temporaryNotification').textContent = '';
});

function fakeXhr({ contentType = 'text/html', message = null, responseText = '' } = {}) {
  const headers = { 'Content-Type': contentType, 'X-Redmine-Message': message };
  return {
    responseText,
    getResponseHeader(name) { return headers[name] ?? null; },
    setRequestHeader: vi.fn()
  };
}

function fire(type, detail) {
  document.dispatchEvent(new CustomEvent(type, { detail }));
}

describe('subscription template list', () => {
  it('attaches the broker token header to outgoing requests', () => {
    document.getElementById('subscription_auth_token').value = 'secret-token';
    const xhr = fakeXhr();
    fire('ajax:beforeSend', [xhr, {}]);
    expect(xhr.setRequestHeader).toHaveBeenCalledWith('FIWARE-Broker-Auth-Token', 'secret-token');
  });

  it('sends no token header while the token box is absent', () => {
    const box = document.getElementById('subscription_auth_token');
    const parent = box.parentNode;
    parent.removeChild(box);
    const xhr = fakeXhr();
    fire('ajax:beforeSend', [xhr, {}]);
    expect(xhr.setRequestHeader).not.toHaveBeenCalled();
    parent.appendChild(box);
  });

  it('swaps the rows and shows the outcome for an HTML response', () => {
    const xhr = fakeXhr({
      contentType: 'text/html; charset=utf-8',
      message: 'Subscription published',
      responseText: '<tr id="replaced"></tr>'
    });
    fire('ajax:success', [null, 'OK', xhr]);
    expect(document.getElementById('replaced')).not.toBeNull();
    expect(document.getElementById('original')).toBeNull();
    expect(document.getElementById('temporaryNotification').textContent).toBe('Subscription published');
  });

  it('leaves the rows alone for a JS response (sync, copy)', () => {
    const xhr = fakeXhr({
      contentType: 'text/javascript; charset=utf-8',
      responseText: 'showNotification("done");'
    });
    fire('ajax:success', [null, 'OK', xhr]);
    expect(document.getElementById('original')).not.toBeNull();
    expect(document.getElementById('temporaryNotification').textContent).toBe('');
  });

  it('shows the outcome header on an error response', () => {
    const xhr = fakeXhr({ message: 'Broker rejected the subscription' });
    fire('ajax:error', [null, 'Bad Request', xhr]);
    expect(document.getElementById('original')).not.toBeNull();
    expect(document.getElementById('temporaryNotification').textContent).toBe('Broker rejected the subscription');
  });
});
