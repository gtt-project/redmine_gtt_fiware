module RedmineGttFiware
  # Generates the instance's self-published JSON-LD context (#69, step 2;
  # task vocabulary since #152). It imports the redmine subject of GTT's
  # node (the datamodels.jp task context plus category) and adds only what
  # is instance-defined: the subtypes, declared rdfs:subClassOf the task
  # vocabulary's Task, and the exposed custom-field terms. Consumers who
  # dereference one URL learn the instance's full schema; the @graph is
  # ignored by @context processing and speaks to RDF tooling.
  class InstanceContext
    RDFS = 'http://www.w3.org/2000/01/rdf-schema#'.freeze
    RDF = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'.freeze

    # base_url: the instance's public base (Setting.host_name-derived, with
    # the request base as fallback for the serving controller only).
    def initialize(base_url)
      @base_url = base_url.to_s.chomp('/')
    end

    def to_h
      {
        '@context' => [EmissionVocabulary::TASK_EXTENSION_CONTEXT, context_terms],
        '@graph' => subtype_classes + custom_field_properties
      }
    end

    # Where instance-defined terms live: the subtypes and the custom-field
    # terms. The task terms deliberately do NOT live here - they mean the
    # same on every instance, so they come from the imported context.
    def vocab_namespace
      "#{@base_url}/fiware/vocab#"
    end

    private

    # An instance term may never redefine a task term (or a prefix):
    # validation rejects such terms (EmissionMapping), and the skip here is
    # defense in depth for rows saved before that rule, so a stray term can
    # never shadow an imported term in the published document.
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

    # One class declaration per distinct configured subtype, anchored to the
    # task vocabulary's Task. The label names the mapped trackers so a human
    # reading the schema can see what feeds each subtype.
    def subtype_classes
      subtypes.map do |subtype, tracker_names|
        {
          '@id' => "inst:#{subtype}",
          '@type' => 'rdfs:Class',
          'rdfs:subClassOf' => { '@id' => EmissionVocabulary::TASK_TYPE_IRI },
          'rdfs:label' => "#{subtype} (tracker: #{tracker_names.uniq.sort.join(', ')})"
        }
      end
    end

    # One property declaration per distinct exposed custom-field term (#69,
    # step 2c), labeled with the source field so schema readers can trace it.
    def custom_field_properties
      custom_terms.map do |term, field_names|
        {
          '@id' => "inst:#{term}",
          '@type' => 'rdf:Property',
          'rdfs:label' => "#{term} (custom field: #{field_names.uniq.sort.join(', ')})"
        }
      end
    end

    def subtypes
      @subtypes ||= EmissionMapping.includes(:tracker).each_with_object({}) do |mapping, result|
        (result[mapping.subtype] ||= []) << mapping.tracker.name
      end
    end

    # term => source field names, custom fields batch-loaded in one query.
    # A term colliding with a subtype is skipped: one inst: IRI must not be
    # published as both a class and a property (validation rejects new
    # collisions; this covers pre-validation rows).
    def custom_terms
      @custom_terms ||= begin
        exposures = EmissionMapping.all.map(&:exposed_custom_fields)
        custom_fields = IssueCustomField.where(id: exposures.flat_map(&:keys).uniq).index_by(&:id)
        exposures.each_with_object({}) do |exposed, result|
          exposed.each do |cf_id, term|
            custom_field = custom_fields[cf_id]
            next unless custom_field
            next if subtypes.key?(term)

            (result[term] ||= []) << custom_field.name
          end
        end
      end
    end
  end
end
