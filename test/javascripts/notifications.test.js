// The shared page helper (gtt_fiware.js): showNotification is a global the
// publish/unpublish/copy/sync responses call by name. It is loaded on every
// page by the layout hook, so it must be a no-op (not a TypeError) on pages
// without the #temporaryNotification box.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { beforeAll, describe, expect, it, vi } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));

beforeAll(() => {
  window.eval(readFileSync(join(here, '../../assets/javascripts/gtt_fiware.js'), 'utf8'));
});

describe('showNotification', () => {
  it('is a no-op on pages without the notification box', () => {
    document.body.innerHTML = '';
    expect(() => window.showNotification('hello')).not.toThrow();
  });

  it('shows the message and hides it again after the timeout', () => {
    vi.useFakeTimers();
    document.body.innerHTML = '<div id="temporaryNotification"></div>';
    window.showNotification('Command copied');

    const box = document.getElementById('temporaryNotification');
    expect(box.textContent).toBe('Command copied');
    expect(box.classList.contains('visible')).toBe(true);

    vi.advanceTimersByTime(3000);
    expect(box.classList.contains('visible')).toBe(false);
    vi.useRealTimers();
  });
});
