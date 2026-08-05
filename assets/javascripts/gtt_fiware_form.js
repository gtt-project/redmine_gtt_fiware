/* Client-side behaviour of the subscription form (#66, #68, #105, #106).
 *
 * Everything the script needs from the server travels through the DOM:
 * data-* attributes, ids and classes rendered by the form partials. The
 * Rails suite pins that DOM contract; the Vitest suite in test/javascripts
 * drives this file against jsdom fixtures.
 *
 * init() is idempotent: it returns early when the form is not present or
 * was already wired (a data flag on the form guards against duplicate
 * listeners). It runs automatically on DOMContentLoaded and is exposed as
 * window.GttFiwareForm.init for the tests.
 */
(function() {
  'use strict';

  function init() {
    var form = document.getElementById('gtt-fiware-connection-select');
    if (!form) { return; }
    form = form.closest('form');
    if (form.dataset.gttFiwareFormInit) { return; }
    form.dataset.gttFiwareFormInit = '1';

    // --- helpers ---------------------------------------------------------

    function jsonModeOn(target) {
      var json = document.getElementById('gtt-fiware-' + target + '-json');
      return json && !json.classList.contains('hidden');
    }

    function toggleJsonMode(target) {
      var rows = document.getElementById('gtt-fiware-' + (target === 'entities' ? 'entity' : 'attachment') + '-rows');
      var json = document.getElementById('gtt-fiware-' + target + '-json');
      if (!rows || !json) { return; }
      var showJson = json.classList.contains('hidden');
      if (showJson) {
        serialize();
      } else if (!restoreRows(target)) {
        // The JSON cannot be shown by the picker; leaving JSON mode would
        // overwrite the hand-edited JSON with stale rows on submit, so the
        // form stays in JSON mode.
        return;
      }
      json.classList.toggle('hidden', !showJson);
      rows.style.display = showJson ? 'none' : '';
    }

    // Rebuilds the picker rows from the JSON field when leaving JSON mode.
    // Returns false when the JSON is not representable by the picker
    // (unparsable, non-array, extra keys, non-string values); the caller
    // then keeps JSON mode, so hand-edited JSON is never lost.
    function restoreRows(target) {
      var config = target === 'entities' ? {
        fieldId: 'subscription_template_entities_string',
        containerId: 'gtt-fiware-entity-rows',
        prototypeId: 'gtt-fiware-entity-prototype',
        rowClass: 'gtt-fiware-entity-row',
        addId: 'gtt-fiware-entity-add',
        rowValues: entityRowValues
      } : {
        fieldId: 'subscription_template_attachments_string',
        containerId: 'gtt-fiware-attachment-rows',
        prototypeId: 'gtt-fiware-attachment-prototype',
        rowClass: 'gtt-fiware-attachment-row',
        addId: 'gtt-fiware-attachment-add',
        rowValues: attachmentRowValues
      };
      var field = document.getElementById(config.fieldId);
      var container = document.getElementById(config.containerId);
      var prototype = document.getElementById(config.prototypeId);
      if (!field || !container || !prototype) { return false; }

      var text = field.value.trim();
      var parsed = [];
      if (text !== '' && text !== 'null') {
        try { parsed = JSON.parse(text); } catch (err) { return false; }
        if (!Array.isArray(parsed)) { return false; }
      }
      var rows = parsed.map(config.rowValues);
      if (rows.some(function(values) { return values === null; })) { return false; }

      container.querySelectorAll('.' + config.rowClass).forEach(function(row) { row.remove(); });
      rows.forEach(function(values) {
        var clone = prototype.content.firstElementChild.cloneNode(true);
        Object.keys(values).forEach(function(selector) {
          var el = clone.querySelector(selector);
          if (el) { el.value = values[selector]; }
        });
        container.insertBefore(clone, document.getElementById(config.addId));
      });
      return true;
    }

    // One picker row per entity selector: a type plus at most one
    // id/idPattern member.
    function entityRowValues(obj) {
      if (!obj || typeof obj !== 'object' || typeof obj.type !== 'string') { return null; }
      var rest = Object.keys(obj).filter(function(key) { return key !== 'type'; });
      // Always set all three inputs: the cloned prototype row carries a
      // default match value that must not leak into a restored row.
      if (rest.length === 0) {
        return { '.js-entity-type': obj.type, '.js-entity-match-kind': 'idPattern', '.js-entity-match-value': '' };
      }
      if (rest.length > 1 || (rest[0] !== 'id' && rest[0] !== 'idPattern')) { return null; }
      if (typeof obj[rest[0]] !== 'string') { return null; }
      return {
        '.js-entity-type': obj.type,
        '.js-entity-match-kind': rest[0],
        '.js-entity-match-value': obj[rest[0]]
      };
    }

    function attachmentRowValues(obj) {
      if (!obj || typeof obj !== 'object' || typeof obj.url !== 'string') { return null; }
      var allowed = ['url', 'filename', 'description'];
      var keys = Object.keys(obj);
      if (keys.some(function(key) { return allowed.indexOf(key) === -1; })) { return null; }
      if (keys.some(function(key) { return typeof obj[key] !== 'string'; })) { return null; }
      return {
        '.js-attachment-url': obj.url,
        '.js-attachment-filename': obj.filename || '',
        '.js-attachment-description': obj.description || ''
      };
    }

    function rowValues(row, selectors) {
      return selectors.map(function(sel) {
        var el = row.querySelector(sel);
        return el ? el.value.trim() : '';
      });
    }

    // --- serialization into the existing *_string / attrs fields ----------

    function serializeEntities() {
      if (jsonModeOn('entities')) { return; }
      var entities = [];
      document.querySelectorAll('.gtt-fiware-entity-row').forEach(function(row) {
        var values = rowValues(row, ['.js-entity-type', '.js-entity-match-kind', '.js-entity-match-value']);
        if (values[0] === '') { return; }
        var entity = { type: values[0] };
        if (values[2] !== '') { entity[values[1]] = values[2]; }
        entities.push(entity);
      });
      var field = document.getElementById('subscription_template_entities_string');
      if (field) { field.value = entities.length ? JSON.stringify(entities) : ''; }
    }

    function serializeAttrs() {
      var input = document.getElementById('gtt-fiware-attrs-input');
      var field = document.getElementById('subscription_template_attrs');
      if (!input || !field) { return; }
      var names = input.value.split(',').map(function(s) { return s.trim(); }).filter(Boolean);
      field.value = names.length ? JSON.stringify(names) : '';
    }

    function serializeGeometry() {
      var mode = form.querySelector('input[name="gtt_fiware_geometry_mode"]:checked');
      var field = document.getElementById('subscription_template_geometry_string');
      if (!mode || !field) { return; }
      // 'null' (not blank) clears a stored geometry: the model skips blank input.
      if (mode.value === 'location') { field.value = '"${location}"'; }
      else if (mode.value === 'none') { field.value = 'null'; }
    }

    function serializeAttachments() {
      if (jsonModeOn('attachments')) { return; }
      var attachments = [];
      document.querySelectorAll('.gtt-fiware-attachment-row').forEach(function(row) {
        var values = rowValues(row, ['.js-attachment-url', '.js-attachment-filename', '.js-attachment-description']);
        if (values[0] === '') { return; }
        var attachment = { url: values[0] };
        if (values[1] !== '') { attachment.filename = values[1]; }
        if (values[2] !== '') { attachment.description = values[2]; }
        attachments.push(attachment);
      });
      var field = document.getElementById('subscription_template_attachments_string');
      if (field) { field.value = attachments.length ? JSON.stringify(attachments) : 'null'; }
    }

    function serializeGeoArea() {
      var mode = form.querySelector('input[name="gtt_fiware_geo_mode"]:checked');
      if (!mode || mode.value === 'custom') { return; }
      var georel = document.getElementById('subscription_template_expression_georel');
      var geometry = document.getElementById('subscription_template_expression_geometry');
      var coords = document.getElementById('subscription_template_expression_coords');
      if (!georel || !geometry || !coords) { return; }
      if (mode.value === 'anywhere') {
        georel.value = ''; geometry.value = ''; coords.value = '';
      } else if (mode.value === 'boundary') {
        var ring;
        try {
          ring = JSON.parse(mode.dataset.geom).geometry.coordinates[0];
        } catch (err) {
          ring = null;
        }
        // data-geom is server-rendered; if it is missing, malformed or not
        // a ring of number pairs, leave the stored triple untouched rather
        // than throwing from inside the submit listener.
        var isPair = function(c) {
          return Array.isArray(c) && typeof c[0] === 'number' && typeof c[1] === 'number';
        };
        if (!Array.isArray(ring) || ring.length === 0 || !ring.every(isPair)) { return; }
        var geom = ring
          .map(function(c) { return [Number(c[1].toFixed(5)), Number(c[0].toFixed(5))]; })
          .join(';');
        georel.value = 'coveredBy'; geometry.value = 'polygon'; coords.value = geom;
      }
    }

    function serialize() {
      serializeEntities();
      serializeAttrs();
      serializeGeometry();
      serializeAttachments();
      serializeGeoArea();
    }

    form.addEventListener('submit', serialize);

    // --- row add/remove ----------------------------------------------------

    function wireRowContainer(containerId, addId, rowClass, prototypeId) {
      var container = document.getElementById(containerId);
      if (!container) { return; }
      container.addEventListener('click', function(e) {
        var remove = e.target.closest('.js-entity-remove, .js-attachment-remove');
        if (remove) {
          e.preventDefault();
          remove.closest('.' + rowClass).remove();
          return;
        }
        if (e.target.closest('#' + addId)) {
          e.preventDefault();
          // Clone the inert <template> prototype, not an existing row: cloning
          // the last row broke as soon as every row had been removed.
          var prototype = document.getElementById(prototypeId);
          if (!prototype) { return; }
          var clone = prototype.content.firstElementChild.cloneNode(true);
          container.insertBefore(clone, document.getElementById(addId));
        }
      });
    }
    wireRowContainer('gtt-fiware-entity-rows', 'gtt-fiware-entity-add', 'gtt-fiware-entity-row', 'gtt-fiware-entity-prototype');
    wireRowContainer('gtt-fiware-attachment-rows', 'gtt-fiware-attachment-add', 'gtt-fiware-attachment-row', 'gtt-fiware-attachment-prototype');

    document.querySelectorAll('.js-json-toggle').forEach(function(link) {
      link.addEventListener('click', function(e) {
        e.preventDefault();
        toggleJsonMode(link.dataset.target);
      });
    });

    // --- mode-dependent visibility ------------------------------------------

    form.querySelectorAll('input[name="gtt_fiware_geo_mode"]').forEach(function(radio) {
      radio.addEventListener('change', function() {
        document.getElementById('gtt-fiware-geo-custom').style.display = radio.value === 'custom' ? '' : 'none';
      });
    });
    form.querySelectorAll('input[name="gtt_fiware_geometry_mode"]').forEach(function(radio) {
      radio.addEventListener('change', function() {
        document.getElementById('gtt-fiware-geometry-custom').classList.toggle('hidden', radio.value !== 'custom');
      });
    });

    // --- standard-aware toggles (#66): the connection decides NGSIv2 vs LD ---

    var connectionSelect = document.getElementById('gtt-fiware-connection-select');

    function applyStandard() {
      var option = connectionSelect.options[connectionSelect.selectedIndex];
      var standard = option ? option.dataset.standard : null;
      var isLd = standard === 'NGSI-LD';
      var known = Boolean(standard);

      document.querySelectorAll('.js-ngsi-v2-only').forEach(function(el) {
        el.style.display = (known && isLd) ? 'none' : '';
      });
      document.querySelectorAll('.js-ngsi-ld-only').forEach(function(el) {
        el.style.display = (known && isLd) ? '' : 'none';
      });
      document.querySelectorAll('.js-alteration-label').forEach(function(code) {
        code.textContent = (known && isLd) ? code.dataset.ld : code.dataset.v2;
      });
      // NGSI-LD has no distinct "change" trigger: entityChange and entityUpdate
      // both map to entityUpdated, so showing both duplicates the label. Fold
      // entityUpdate into entityChange and hide it while an LD connection is
      // selected.
      var updateChoice = document.querySelector('.js-alteration-choice[data-type="entityUpdate"]');
      var changeChoice = document.querySelector('.js-alteration-choice[data-type="entityChange"]');
      if (updateChoice && changeChoice) {
        var updateBox = updateChoice.querySelector('input[type="checkbox"]');
        var changeBox = changeChoice.querySelector('input[type="checkbox"]');
        if (known && isLd && updateBox.checked) {
          changeBox.checked = true;
          updateBox.checked = false;
        }
        updateChoice.style.display = (known && isLd) ? 'none' : '';
      }
      // 'oneshot' is an NGSIv2-only concept (#16 test plan follow-up).
      var statusSelect = document.getElementById('gtt-fiware-status-select');
      if (statusSelect) {
        Array.prototype.forEach.call(statusSelect.options, function(opt) {
          if (opt.value === 'oneshot') {
            opt.hidden = known && isLd;
            opt.disabled = known && isLd;
            if (opt.selected && known && isLd) { statusSelect.value = 'active'; }
          }
        });
      }
      // Create-and-publish only works server-side with a stored token.
      var publishButton = document.querySelector('input[name="publish_after_create"]');
      if (publishButton) {
        publishButton.style.display = (option && option.dataset.authMode === 'stored') ? '' : 'none';
      }
    }

    connectionSelect.addEventListener('change', applyStandard);
    applyStandard();

    // --- tracker-driven issue details (#103) ----------------------------------
    // Core fields the selected tracker disables are hidden, and the issue
    // status select is refetched for the tracker/member pair so it offers
    // the same statuses the regular issue form would.

    var trackerSelect = document.getElementById('subscription_template_tracker_id');
    var memberSelect = document.getElementById('subscription_template_member_id');
    var issueStatusSelect = document.getElementById('subscription_template_issue_status_id');

    function applyTrackerFields() {
      if (!trackerSelect || !trackerSelect.dataset.disabledFields) { return; }
      var disabled = JSON.parse(trackerSelect.dataset.disabledFields)[trackerSelect.value] || [];
      document.querySelectorAll('.js-issue-core-field').forEach(function(p) {
        var hidden = disabled.indexOf(p.dataset.field) !== -1;
        p.style.display = hidden ? 'none' : '';
        // A hidden select would still submit its value; clear it so the form
        // matches what the model persists (it clears tracker-disabled fields
        // server-side too).
        if (hidden) {
          p.querySelectorAll('select').forEach(function(select) { select.value = ''; });
        }
      });
      // Custom field groups (#103, phase 2): show the selected tracker's
      // group; hidden groups are disabled so their inputs never submit.
      document.querySelectorAll('.js-tracker-custom-fields').forEach(function(group) {
        var active = group.dataset.trackerId === trackerSelect.value;
        group.style.display = active ? '' : 'none';
        group.disabled = !active;
      });
    }

    // Guards against out-of-order responses: rapid tracker/member changes
    // fire concurrent fetches, and without the token the last response to
    // ARRIVE would rebuild the select, which may belong to the first
    // request SENT (a stale tracker's statuses shown for the current one).
    var statusRequestToken = 0;

    function refreshIssueStatuses() {
      if (!issueStatusSelect || !issueStatusSelect.dataset.statusesUrl) { return; }
      var url = issueStatusSelect.dataset.statusesUrl +
        '?tracker_id=' + encodeURIComponent(trackerSelect ? trackerSelect.value : '') +
        '&member_id=' + encodeURIComponent(memberSelect ? memberSelect.value : '');
      var token = ++statusRequestToken;
      fetch(url, { headers: { 'Accept': 'application/json' } })
        .then(function(response) { return response.json(); })
        .then(function(statuses) {
          if (token !== statusRequestToken) { return; }
          var current = issueStatusSelect.value;
          var currentText = issueStatusSelect.selectedOptions[0] ?
            issueStatusSelect.selectedOptions[0].textContent : '';
          issueStatusSelect.innerHTML = '';
          statuses.forEach(function(status) {
            var option = document.createElement('option');
            option.value = String(status.id);
            option.textContent = status.name;
            issueStatusSelect.appendChild(option);
          });
          // Keep the previous choice even when the new pair would not offer
          // it: silently changing a stored value is worse than showing it.
          if (current && !issueStatusSelect.querySelector('option[value="' + current + '"]')) {
            var keep = document.createElement('option');
            keep.value = current;
            keep.textContent = currentText;
            issueStatusSelect.appendChild(keep);
          }
          if (current) { issueStatusSelect.value = current; }
          if (issueStatusSelect.selectedIndex === -1) { issueStatusSelect.selectedIndex = 0; }
        })
        .catch(function() { /* keep the current list when the lookup fails */ });
    }

    if (trackerSelect) {
      trackerSelect.addEventListener('change', function() {
        applyTrackerFields();
        refreshIssueStatuses();
      });
      applyTrackerFields();
    }
    if (memberSelect) {
      memberSelect.addEventListener('change', refreshIssueStatuses);
    }

    // --- live preview (#68) ---------------------------------------------------

    function previewEntityType() {
      var rows = document.getElementById('gtt-fiware-entity-rows');
      if (rows && rows.style.display !== 'none') {
        var input = rows.querySelector('.js-entity-type');
        if (input && input.value.trim() !== '') { return input.value.trim(); }
      }
      var json = document.getElementById('subscription_template_entities_string');
      if (json && json.value.trim() !== '') {
        try {
          var entities = JSON.parse(json.value);
          if (Array.isArray(entities) && entities[0] && entities[0].type) { return entities[0].type; }
        } catch (err) { /* fall through */ }
      }
      return '';
    }

    var previewButton = document.getElementById('gtt-fiware-preview-button');
    // Same out-of-order guard as the status refetch: a double-click fires
    // two requests, and only the latest one may write the result box.
    var previewRequestToken = 0;
    if (previewButton) {
      previewButton.addEventListener('click', function(e) {
        e.preventDefault();
        var out = document.getElementById('gtt-fiware-preview-result');
        if (!out) { return; }
        var token = ++previewRequestToken;
        out.style.display = '';
        out.textContent = previewButton.dataset.loading;

        var field = function(id) {
          var el = document.getElementById(id);
          return el ? el.value : '';
        };
        var csrf = document.querySelector('meta[name="csrf-token"]');

        fetch(previewButton.dataset.url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf ? csrf.content : ''
          },
          body: JSON.stringify({
            broker_connection_id: connectionSelect.value,
            entity_type: previewEntityType(),
            subject: field('subscription_template_subject'),
            description: field('subscription_template_description'),
            notes: field('subscription_template_notes')
          })
        }).then(function(response) {
          return response.json().then(function(json) { return { ok: response.ok, json: json }; });
        }).then(function(result) {
          if (token !== previewRequestToken) { return; }
          if (!result.ok) {
            out.textContent = result.json.error || previewButton.dataset.error;
            return;
          }
          out.innerHTML = '';
          [result.json.subject, result.json.description, result.json.notes].forEach(function(text) {
            if (!text) { return; }
            var pre = document.createElement('pre');
            pre.textContent = text;
            out.appendChild(pre);
          });
          var em = document.createElement('em');
          em.className = 'info';
          em.textContent = previewButton.dataset.entityLabel + ' ' + result.json.entity_id +
            (result.json.has_geometry ? ', ' + previewButton.dataset.geometryLabel : '');
          out.appendChild(em);
        }).catch(function() {
          if (token !== previewRequestToken) { return; }
          out.textContent = previewButton.dataset.error;
        });
      });
    }
  }

  window.GttFiwareForm = { init: init };
  document.addEventListener('DOMContentLoaded', init);
})();
