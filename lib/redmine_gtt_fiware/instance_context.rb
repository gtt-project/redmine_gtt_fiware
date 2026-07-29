module RedmineGttFiware
  # Generates the instance's self-published JSON-LD context (#69, step 2):
  # the core Issue vocabulary terms plus one class per configured emission
  # subtype, each declared rdfs:subClassOf the core Issue. Consumers who
  # dereference one URL learn the instance's full schema; the @graph is
  # ignored by @context processing and speaks to RDF tooling.
  class InstanceContext
    # The published core vocabulary namespace. The core terms are frozen (see
    # IssueEntity): renaming any of them is a breaking change for every
    # consumer of every instance.
    CORE_NAMESPACE = 'https://gtt-project.org/ns/fiware#'.freeze
    CORE_TERMS = %w[Issue title status statusLabel subtype source refersTo].freeze
    # The admin-exposable standard field terms (#69, step 2b). Published for
    # every instance whether exposed or not: exposure gates what an instance
    # emits, the vocabulary defines what the words mean.
    STANDARD_TERMS = %w[description priority category targetVersion startDate
                        dueDate estimatedTime percentDone parent assignee].freeze
    RDFS = 'http://www.w3.org/2000/01/rdf-schema#'.freeze
    RDF = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'.freeze

    # base_url: the instance's public base (Setting.host_name-derived, with
    # the request base as fallback for the serving controller only).
    def initialize(base_url)
      @base_url = base_url.to_s.chomp('/')
    end

    def to_h
      {
        '@context' => context_terms,
        '@graph' => subtype_classes + custom_field_properties
      }
    end

    # Where instance-defined terms live: the subtypes now, the custom-field
    # terms of step 2c later. The standard field terms deliberately do NOT
    # live here - they mean the same on every instance, so they belong to the
    # shared namespace (see STANDARD_TERMS).
    def vocab_namespace
      "#{@base_url}/fiware/vocab#"
    end

    private

    def context_terms
      terms = {
        'rdf' => RDF,
        'rdfs' => RDFS,
        'gttfiware' => CORE_NAMESPACE,
        'inst' => vocab_namespace
      }
      (CORE_TERMS + STANDARD_TERMS).each { |term| terms[term] = "gttfiware:#{term}" }
      # Relationship terms point at other entities, so they expand as IRIs,
      # not strings.
      terms['refersTo'] = { '@id' => 'gttfiware:refersTo', '@type' => '@id' }
      terms['parent'] = { '@id' => 'gttfiware:parent', '@type' => '@id' }
      # Validation rejects reserved subtype and custom terms (EmissionMapping);
      # the skip is defense in depth for pre-validation rows, so a stray term
      # can never shadow a core term or prefix in the published document.
      subtypes.each_key { |subtype| terms[subtype] = "inst:#{subtype}" unless terms.key?(subtype) }
      custom_terms.each_key { |term| terms[term] = "inst:#{term}" unless terms.key?(term) }
      terms
    end

    # One class declaration per distinct configured subtype, anchored to the
    # core Issue. The label names the mapped trackers so a human reading the
    # schema can see what feeds each subtype.
    def subtype_classes
      subtypes.map do |subtype, tracker_names|
        {
          '@id' => "inst:#{subtype}",
          '@type' => 'rdfs:Class',
          'rdfs:subClassOf' => { '@id' => 'gttfiware:Issue' },
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
