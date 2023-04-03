class UserPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'users', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'User',
      "login": {
        "type": 'Property',
        "value": @object.login
      },
      "firstName": {
        "type": 'Property',
        "value": @object.firstname
      },
      "lastName": {
        "type": 'Property',
        "value": @object.lastname
      },
      "email": {
        "type" => 'Property',
        "value" => (User.current.admin? || !@object.pref.hide_mail) ? @object.mail : nil
      },
      "status": {
        "type" => 'Property',
        "value" => User.current.admin ? @object.status : nil
      },
      "lastLoginDate": {
        "type": 'Property',
        "value": @object.last_login_on
      },
      "createdAt": {
        "type": 'Property',
        "value": @object.created_on
      },
      "modifiedAt": {
        "type": 'Property',
        "value": @object.updated_on
      },
    }

    # TODO: optional includes

    if @object.geom
      json[:location] = {
        "type": 'GeoProperty',
        "value": @object.geojson['geometry']
      }
    else
      json[:location] = nil
    end

    # Handle custom fields
    CustomFieldHelper.process_custom_fields(json, @object.visible_custom_field_values, @view_context, @normalized)

    render_ngsi(json)
  end
end
