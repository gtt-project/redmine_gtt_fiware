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
    RDFS = 'http://www.w3.org/2000/01/rdf-schema#'.freeze

    # base_url: the instance's public base (Setting.host_name-derived, with
    # the request base as fallback for the serving controller only).
    def initialize(base_url)
      @base_url = base_url.to_s.chomp('/')
    end

    def to_h
      {
        '@context' => context_terms,
        '@graph' => subtype_classes
      }
    end

    # Where instance-defined terms (subtypes, later attributes) live.
    def vocab_namespace
      "#{@base_url}/fiware/vocab#"
    end

    private

    def context_terms
      terms = {
        'rdfs' => RDFS,
        'gttfiware' => CORE_NAMESPACE,
        'inst' => vocab_namespace
      }
      CORE_TERMS.each { |term| terms[term] = "gttfiware:#{term}" }
      # refersTo points at another entity, so it expands as an IRI, not a string.
      terms['refersTo'] = { '@id' => 'gttfiware:refersTo', '@type' => '@id' }
      # Validation rejects reserved subtype names (EmissionMapping); the skip
      # is defense in depth for pre-validation rows, so a stray subtype can
      # never shadow a core term or prefix in the published document.
      subtypes.each_key { |subtype| terms[subtype] = "inst:#{subtype}" unless terms.key?(subtype) }
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

    def subtypes
      @subtypes ||= EmissionMapping.includes(:tracker).each_with_object({}) do |mapping, result|
        (result[mapping.subtype] ||= []) << mapping.tracker.name
      end
    end
  end
end
