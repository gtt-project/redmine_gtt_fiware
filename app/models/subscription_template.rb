class SubscriptionTemplate < ActiveRecord::Base
  belongs_to :project, optional: false
  belongs_to :tracker, optional: false
  belongs_to :issue_status, optional: false

  validates :name, presence: true
  validate :name_uniqueness

  validates :entities_string, presence: true
  validates :subject, presence: true
  validates :description, presence: true

  validate :take_json_entities
  validate :take_json_condition

  attr_writer :entities_string
  def entities_string
    @entities_string ||= entities.present? ? JSON.pretty_generate(entities) : ''
  end

  attr_writer :condition_string
  def condition_string
    @condition_string ||= condition.present? ? JSON.pretty_generate(condition) : ''
  end

  private

  def take_json_entities
    self.entities = JSON.parse(entities_string)
  rescue JSON::ParserError
    errors.add :entities_string, I18n.t(:error_invalid_json)
  end

  def take_json_condition
    if condition_string.present?
      self.condition = JSON.parse(condition_string)
    else
      self.condition = nil
    end
  rescue JSON::ParserError
    errors.add :condition_string, I18n.t(:error_invalid_json)
  end

  def name_uniqueness
    scope = SubscriptionTemplate.where.not(id: id).where(name: name, project_id: project_id)

    if scope.any?
      errors.add :name, I18n.t('model.subscription_template.name_uniqueness')
    end
  end
end
