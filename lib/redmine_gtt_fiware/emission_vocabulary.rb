module RedmineGttFiware
  # The emission vocabulary (#152): the neutral task vocabulary of the
  # datamodels.jp catalog (`Task`, https://datamodels.jp/ns/task/), plus the
  # GTT node's redmine subject for what Task lacks (category).
  #
  # The redmine subject (0.2.0 and later) names the model with Redmine's
  # word: in its context the short name `Issue` expands to datamodels.jp's
  # Task IRI and `Task` is unset, so emitted entities read `type: Issue`
  # while brokers store the same IRI as any datamodels.jp Task.
  #
  # Entity ids do not depend on the vocabulary (IssueUrn), so the ids of
  # entities emitted before the switch to Task-only emission stay valid.
  module EmissionVocabulary
    # The @context of the redmine subject on GTT's data model node
    # (https://models.gtt-project.org/ns/redmine): imports the datamodels.jp
    # task context and adds only `category`. v0 follows the subject's 0.x
    # versions.
    TASK_EXTENSION_CONTEXT = 'https://models.gtt-project.org/context/redmine/v0.jsonld'.freeze
    # The task vocabulary itself, for consumers that only read task terms
    # (federation queries and watches).
    TASK_CONTEXT = 'https://datamodels.jp/context/task/v1.jsonld'.freeze
    TASK_NAMESPACE = 'https://datamodels.jp/ns/task/'.freeze
    TASK_TYPE_IRI = "#{TASK_NAMESPACE}Task".freeze

    # The type of emitted entities: the redmine subject's name for
    # TASK_TYPE_IRI.
    ENTITY_TYPE = 'Issue'.freeze

    # How that one type can come back from a broker, depending on the context
    # it compacts with: the redmine subject's name, datamodels.jp's name, or
    # the IRI itself when the context defines neither.
    TYPE_NAMES = [ENTITY_TYPE, 'Task', TASK_TYPE_IRI].freeze

    # Every term the task contexts define: every key of the imported
    # datamodels.jp task context (the attributes of Task, Project and
    # Milestone, and the subject's types), the redmine subject's terms
    # (Issue, category), and the prefixes of the imported contexts. Task is
    # unset by the redmine subject but stays reserved: it is datamodels.jp's
    # name for the same type.
    # Subtypes and custom-field terms must not shadow any of them
    # (EmissionMapping, InstanceContext).
    TASK_TERMS = %w[
      Task Issue Project Milestone
      name description project milestone parent relatedTo refersTo progress
      statusLabel subtype priority assignee author start due completedAt
      estimatedDuration percentComplete keywords location spatialId isPrivate
      source externalId dateCreated dateModified
      end homepage identifier isPublic milestoneStatus projectStatus
      category
      tm schema redmine
    ].freeze
  end
end
