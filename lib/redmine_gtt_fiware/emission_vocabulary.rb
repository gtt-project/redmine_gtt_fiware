module RedmineGttFiware
  # The emission vocabulary (#152): the neutral task vocabulary of the
  # datamodels.jp catalog (`Task`, https://datamodels.jp/ns/task/), plus the
  # GTT node's redmine subject for what Task lacks (category).
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

    # Every term the task contexts define: every key of the imported
    # datamodels.jp task context (the attributes of Task, Project and
    # Milestone, and the subject's types), the redmine subject's term, and
    # the prefixes of the imported contexts.
    # Subtypes and custom-field terms must not shadow any of them
    # (EmissionMapping, InstanceContext).
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
  end
end
