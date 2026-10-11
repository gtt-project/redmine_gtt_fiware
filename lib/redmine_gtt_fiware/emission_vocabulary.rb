module RedmineGttFiware
  # The instance-wide choice of emission vocabulary (#152):
  #
  # - gtt: the frozen GTT core (`Issue`, https://gtt-project.org/ns/fiware).
  #   The default; existing instances keep emitting exactly what they did.
  # - task: the neutral task vocabulary of the datamodels.jp catalog
  #   (`Task`, https://datamodels.jp/ns/task/), plus the GTT node's redmine
  #   subject for what Task lacks (category).
  #
  # Entity ids do not depend on this choice (IssueUrn either way), so an
  # admin can switch without re-identifying anything, and federation's echo
  # guard and attribution keep working across instances that chose
  # differently.
  module EmissionVocabulary
    SETTING = 'fiware_emission_vocabulary'.freeze
    GTT = 'gtt'.freeze
    TASK = 'task'.freeze
    ALL = [GTT, TASK].freeze
    DEFAULT = GTT

    # The @context of the redmine subject on GTT's data model node
    # (https://models.gtt-project.org/ns/redmine): imports the datamodels.jp
    # task context and adds only `category`. v0 follows the subject's 0.x
    # versions.
    TASK_EXTENSION_CONTEXT = 'https://models.gtt-project.org/context/redmine/v0.jsonld'.freeze
    # The task vocabulary itself, for consumers that only read task terms
    # (federation queries).
    TASK_CONTEXT = 'https://datamodels.jp/context/task/v1.jsonld'.freeze
    TASK_NAMESPACE = 'https://datamodels.jp/ns/task/'.freeze
    TASK_TYPE_IRI = "#{TASK_NAMESPACE}Task".freeze

    # Every term the task-mode contexts define: every key of the imported
    # datamodels.jp task context (the attributes of Task, Project and
    # Milestone, and the subject's types), the redmine subject's term, and
    # the prefixes of the imported contexts.
    # Subtypes and custom-field terms must not shadow any of them in task
    # mode (EmissionMapping, TaskInstanceContext).
    TASK_TERMS = %w[
      Task Project Milestone
      name description project milestone parent relatedTo refersTo progress
      statusLabel subtype priority assignee author start due completedAt
      estimatedDuration percentComplete keywords location spatialId isPrivate
      source externalId dateCreated dateModified
      end homepage identifier isPublic milestoneStatus projectStatus
      category
      tm schema redmine
    ].freeze

    module_function

    # Unknown or missing values fall back to the default, so a hand-edited
    # setting can never switch an instance away from the frozen core.
    def current
      value = RedmineGttFiware.settings[SETTING].to_s.strip
      ALL.include?(value) ? value : DEFAULT
    end

    def task?
      current == TASK
    end
  end
end
