module RedmineGttFiware
  # The instance's self-published JSON-LD context for the task vocabulary
  # (#152), served next to the GTT one. It imports GTT's extension of the
  # datamodels.jp task context and adds only what is instance-defined: the
  # subtypes, declared rdfs:subClassOf the task vocabulary's Task, and the
  # exposed custom-field terms. Both live under the same instance namespace
  # as in the GTT context, since they mean the same thing in either mode.
  class TaskInstanceContext < InstanceContext
    def to_h
      {
        '@context' => [EmissionVocabulary::TASK_EXTENSION_CONTEXT, context_terms],
        '@graph' => subtype_classes + custom_field_properties
      }
    end

    private

    # The task terms come from the imported context. An instance term may
    # never redefine one of them (or a prefix): validation rejects such terms
    # in task mode, and the skip here covers rows saved while the instance
    # still emitted the GTT vocabulary, where they were legal.
    def context_terms
      terms = {
        'rdf' => RDF,
        'rdfs' => RDFS,
        'inst' => vocab_namespace
      }
      reserved = (EmissionVocabulary::TASK_TERMS + terms.keys).map(&:downcase)
      (subtypes.keys + custom_terms.keys).each do |term|
        next if reserved.include?(term.downcase) || terms.key?(term)

        terms[term] = "inst:#{term}"
      end
      terms
    end

    def superclass_iri
      EmissionVocabulary::TASK_TYPE_IRI
    end
  end
end
