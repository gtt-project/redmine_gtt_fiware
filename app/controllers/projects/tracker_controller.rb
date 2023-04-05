module Projects
  class TrackerController < ApplicationController
    accept_api_auth :index
    before_action :find_project_by_project_id, :find_tracker_by_tracker_id, :authorize_view_tracker_field_definitions

    def index
      meta_fields = default_fields_for_tracker(@tracker)
      standard_fields = standard_fields_for_tracker(@tracker)
      custom_fields = custom_fields_for_tracker(@tracker, @project, User.current)

      # TODO: Handle GTT geometry field(s)

      response = {
        meta: meta_fields,
        standard: standard_fields,
        custom: custom_fields
      }

      respond_to do |format|
        format.api { render json: response.to_json }
      end
    end

    private

    def find_project_by_project_id
      @project = Project.find_by(id: params[:project_id]) || Project.find_by(identifier: params[:project_id])
      render_404 if @project.nil?
    end

    def find_tracker_by_tracker_id
      @tracker = Tracker.find(params[:tracker_id])
    end

    def authorize_view_tracker_field_definitions
      deny_access unless User.current.allowed_to?(:view_tracker_field_definitions, @project)
    end

    def default_fields_for_tracker(tracker)
      [
        { name: "name", required: true },
        { name: "default_status", required: true },
        { name: "is_in_roadmap", required: false },
        { name: "description", required: false }
      ]
    end

    def standard_fields_for_tracker(tracker)
      Hash[Tracker::CORE_FIELDS.zip([false] * Tracker::CORE_FIELDS.size)]
        .except(*tracker.disabled_core_fields.map(&:to_s))
        .merge(
          "project_id" => true,
          "tracker_id" => true,
          "subject" => true,
          "status_id" => true,
          "priority_id" => true
        )
        .map { |name, required| { name: name, required: required } }
    end

    def custom_fields_for_tracker(tracker, project, user)
      tracker.custom_fields.visible(user)
        .where("is_for_all = ? OR id IN (?)", true, project.all_issue_custom_fields.pluck(:id))
        .map do |field|
          {
            id: field.id,
            name: field.name,
            description: field.description,
            is_required: field.is_required,
            field_format: field.field_format,
            possible_values: field.possible_values.presence,
            regexp: field.regexp.presence,
            min_length: field.min_length.presence,
            max_length: field.max_length.presence,
            default_value: field.default_value.presence,
            position: field.position.presence,
            multiple: field.multiple,
          }
        end
    end

  end
end
