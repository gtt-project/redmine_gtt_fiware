// Fixture builders for the subscription-form tests (#106).
//
// The HTML mirrors the DOM contract the Rails suite pins on the ERB side:
// the ids, classes and data-* attributes in _form_basics, _form_filters,
// _form_issue_details, _form_subscription_options, _entity_row and
// _attachment_row. If a hook changes there, change it here too - the Rails
// DOM-contract tests and these fixtures describe the same interface.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(
  join(here, '../../../assets/javascripts/gtt_fiware_form.js'), 'utf8'
);

// Evaluate the plain browser file in the jsdom window. DOMContentLoaded has
// already fired when vitest hands us the environment, so tests call init()
// explicitly after building their fixture.
export function loadScript() {
  window.eval(source);
}

export function initForm() {
  window.GttFiwareForm.init();
}

export function entityRow({ type = '', kind = 'idPattern', value = '' } = {}) {
  return `
    <span class="gtt-fiware-entity-row">
      <input type="text" class="js-entity-type" value="${type}" />
      <select class="js-entity-match-kind">
        <option value="idPattern" ${kind === 'idPattern' ? 'selected' : ''}>ID pattern</option>
        <option value="id" ${kind === 'id' ? 'selected' : ''}>ID</option>
      </select>
      <input type="text" class="js-entity-match-value" value="${value}" />
      <a href="#" class="js-entity-remove">remove</a>
    </span>`;
}

export function attachmentRow({ url = '', filename = '', description = '' } = {}) {
  return `
    <span class="gtt-fiware-attachment-row">
      <input type="text" class="js-attachment-url" value="${url}" />
      <input type="text" class="js-attachment-filename" value="${filename}" />
      <input type="text" class="js-attachment-description" value="${description}" />
      <a href="#" class="js-attachment-remove">remove</a>
    </span>`;
}

// A polygon around Yoyogi Park, GeoJSON [lon, lat] order like the project
// boundary the ERB embeds in data-geom.
export const BOUNDARY_GEOM = JSON.stringify({
  geometry: {
    coordinates: [[[139.69, 35.67], [139.7, 35.68], [139.695, 35.675], [139.69, 35.67]]]
  }
});

export function buildForm({
  standard = 'NGSI-LD',
  authMode = 'stored',
  connectionSelected = true,
  entities = [],
  entitiesJsonMode = false,
  attachments = [],
  attrs = '',
  geometryMode = 'location',
  geoMode = 'anywhere',
  status = 'active',
  alterationChecked = ['entityCreate', 'entityChange']
} = {}) {
  const checked = (type) => (alterationChecked.includes(type) ? 'checked' : '');
  const ldTriggers = {
    entityCreate: 'entityCreated', entityChange: 'entityUpdated',
    entityUpdate: 'entityUpdated', entityDelete: 'entityDeleted'
  };
  const alterationChoices = Object.entries(ldTriggers).map(([type, ld]) => `
    <span class="js-alteration-choice" data-type="${type}">
      <input type="checkbox" name="subscription_template[alteration_types][]" value="${type}" ${checked(type)} />
      <code class="js-alteration-label" data-v2="${type}" data-ld="${ld}">${type}</code>
    </span>`).join('');

  document.body.innerHTML = `
    <meta name="csrf-token" content="test-csrf" />
    <form>
      <select id="gtt-fiware-connection-select">
        <option value="">-- pick --</option>
        <option value="1" data-standard="${standard}" data-auth-mode="${authMode}"
                ${connectionSelected ? 'selected' : ''}>Broker</option>
      </select>

      <span id="gtt-fiware-entity-rows" ${entitiesJsonMode ? 'style="display:none;"' : ''}>
        ${entities.map(entityRow).join('')}
        <a href="#" id="gtt-fiware-entity-add">Add entity filter</a>
        <template id="gtt-fiware-entity-prototype">${entityRow({ type: '', kind: 'idPattern', value: '.*' })}</template>
      </span>
      <a href="#" class="js-json-toggle" data-target="entities">Edit as JSON</a>
      <p id="gtt-fiware-entities-json" ${entitiesJsonMode ? '' : 'class="hidden"'}>
        <input type="text" id="subscription_template_entities_string" value="" />
      </p>

      <input type="text" id="gtt-fiware-attrs-input" value="${attrs}" />
      <input type="hidden" id="subscription_template_attrs" value="" />

      <label><input type="radio" name="gtt_fiware_geo_mode" value="anywhere" ${geoMode === 'anywhere' ? 'checked' : ''} /> Anywhere</label>
      <label><input type="radio" name="gtt_fiware_geo_mode" value="boundary" ${geoMode === 'boundary' ? 'checked' : ''} data-geom='${BOUNDARY_GEOM}' /> Boundary</label>
      <label><input type="radio" name="gtt_fiware_geo_mode" value="custom" ${geoMode === 'custom' ? 'checked' : ''} /> Custom</label>
      <span id="gtt-fiware-geo-custom" ${geoMode === 'custom' ? '' : 'style="display:none;"'}>
        <input type="text" id="subscription_template_expression_georel" value="" />
        <select id="subscription_template_expression_geometry">
          <option value=""></option><option value="polygon">polygon</option>
        </select>
        <input type="text" id="subscription_template_expression_coords" value="" />
      </span>

      <p>${alterationChoices}</p>
      <em class="info js-ngsi-ld-only" style="display:none;">LD hint</em>
      <p class="js-ngsi-v2-only"><input type="checkbox" id="metadata-change" /></p>

      <label><input type="radio" name="gtt_fiware_geometry_mode" value="location" ${geometryMode === 'location' ? 'checked' : ''} /> Entity location</label>
      <label><input type="radio" name="gtt_fiware_geometry_mode" value="custom" ${geometryMode === 'custom' ? 'checked' : ''} /> Custom</label>
      <label><input type="radio" name="gtt_fiware_geometry_mode" value="none" ${geometryMode === 'none' ? 'checked' : ''} /> None</label>
      <span id="gtt-fiware-geometry-custom" ${geometryMode === 'custom' ? '' : 'class="hidden"'}>
        <textarea id="subscription_template_geometry_string"></textarea>
      </span>

      <span id="gtt-fiware-attachment-rows">
        ${attachments.map(attachmentRow).join('')}
        <a href="#" id="gtt-fiware-attachment-add">Add attachment</a>
        <template id="gtt-fiware-attachment-prototype">${attachmentRow()}</template>
      </span>
      <a href="#" class="js-json-toggle" data-target="attachments">Edit as JSON</a>
      <p id="gtt-fiware-attachments-json" class="hidden">
        <input type="text" id="subscription_template_attachments_string" value="" />
      </p>

      <select id="gtt-fiware-status-select">
        <option value="active" ${status === 'active' ? 'selected' : ''}>active</option>
        <option value="inactive" ${status === 'inactive' ? 'selected' : ''}>inactive</option>
        <option value="oneshot" ${status === 'oneshot' ? 'selected' : ''}>oneshot</option>
      </select>

      <input type="submit" name="publish_after_create" value="Create and publish" />
    </form>`;
}

export function submitForm() {
  const form = document.querySelector('form');
  form.dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
}

export function selectConnection(value) {
  const select = document.getElementById('gtt-fiware-connection-select');
  select.value = value;
  select.dispatchEvent(new window.Event('change', { bubbles: true }));
}
