// Tracker-driven issue details (#103): core fields the selected tracker
// disables are hidden, and the issue status select is refetched for the
// tracker/member pair.

import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { buildForm, initForm, loadScript } from './support/form_fixture.js';

beforeAll(loadScript);
afterEach(() => vi.unstubAllGlobals());

const qs = (sel) => document.querySelector(sel);
const trackerSelect = () => document.getElementById('subscription_template_tracker_id');
const statusSelect = () => document.getElementById('subscription_template_issue_status_id');

function changeTracker(value) {
  trackerSelect().value = value;
  trackerSelect().dispatchEvent(new window.Event('change', { bubbles: true }));
}

function stubStatuses(statuses) {
  const calls = [];
  vi.stubGlobal('fetch', (url) => {
    calls.push(url);
    return Promise.resolve({ json: () => Promise.resolve(statuses) });
  });
  return calls;
}

// fetch resolution is async; one macrotask tick lets the handlers run.
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('disabled core fields', () => {
  it('hides the fields the selected tracker disables, on init and on change', () => {
    buildForm({ selectedTracker: '2' });
    initForm();
    expect(qs('[data-field="category_id"]').style.display).toBe('none');
    expect(qs('[data-field="fixed_version_id"]').style.display).toBe('none');
    expect(qs('[data-field="priority_id"]').style.display).toBe('');

    stubStatuses([]);
    changeTracker('1');
    expect(qs('[data-field="category_id"]').style.display).toBe('');
    expect(qs('[data-field="fixed_version_id"]').style.display).toBe('');
  });

  it('enables the selected tracker custom-field group and disables the others', () => {
    buildForm({ selectedTracker: '1' });
    initForm();
    const group1 = qs('.js-tracker-custom-fields[data-tracker-id="1"]');
    const group2 = qs('.js-tracker-custom-fields[data-tracker-id="2"]');
    expect(group1.disabled).toBe(false);
    expect(group2.disabled).toBe(true);
    expect(group2.style.display).toBe('none');

    stubStatuses([]);
    changeTracker('2');
    expect(group1.disabled).toBe(true);
    expect(group1.style.display).toBe('none');
    expect(group2.disabled).toBe(false);
    expect(group2.style.display).toBe('');
  });

  it('clears a hidden select so it does not submit a stale value', () => {
    buildForm();
    initForm();
    const category = qs('[data-field="category_id"] select');
    category.innerHTML = '<option value=""></option><option value="7" selected>Bugs</option>';
    stubStatuses([]);
    changeTracker('2');
    expect(category.value).toBe('');
  });
});

describe('status refetch', () => {
  it('asks the endpoint for the tracker/member pair', async () => {
    buildForm();
    initForm();
    const calls = stubStatuses([{ id: 1, name: 'New' }]);
    changeTracker('2');
    await tick();
    expect(calls).toHaveLength(1);
    expect(calls[0]).toContain('tracker_id=2');
    expect(calls[0]).toContain('member_id=10');
  });

  it('rebuilds the select and keeps the current choice when still offered', async () => {
    buildForm({ selectedIssueStatus: '2' });
    initForm();
    stubStatuses([{ id: 2, name: 'In Progress' }, { id: 3, name: 'Resolved' }]);
    changeTracker('2');
    await tick();
    const values = Array.from(statusSelect().options).map(o => o.value);
    expect(values).toEqual(['2', '3']);
    expect(statusSelect().value).toBe('2');
  });

  it('appends the stored choice when the new pair does not offer it', async () => {
    buildForm({ selectedIssueStatus: '1' });
    initForm();
    stubStatuses([{ id: 3, name: 'Resolved' }]);
    changeTracker('2');
    await tick();
    const options = Array.from(statusSelect().options).map(o => [o.value, o.textContent]);
    expect(options).toEqual([['3', 'Resolved'], ['1', 'New']]);
    expect(statusSelect().value).toBe('1');
  });

  it('refetches when the member changes', async () => {
    buildForm();
    initForm();
    const calls = stubStatuses([{ id: 1, name: 'New' }]);
    const member = document.getElementById('subscription_template_member_id');
    member.value = '11';
    member.dispatchEvent(new window.Event('change', { bubbles: true }));
    await tick();
    expect(calls).toHaveLength(1);
    expect(calls[0]).toContain('member_id=11');
  });

  it('keeps the current list when the lookup fails', async () => {
    buildForm();
    initForm();
    vi.stubGlobal('fetch', () => Promise.reject(new Error('down')));
    changeTracker('2');
    await tick();
    expect(Array.from(statusSelect().options)).toHaveLength(2);
  });
});
