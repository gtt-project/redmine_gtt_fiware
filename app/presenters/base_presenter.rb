class BasePresenter
  def initialize(object, normalized, ngsiv2, view_context)
    @object = object
    @normalized = normalized
    @ngsiv2 = ngsiv2
    @view_context = view_context
  end

  def as_json
    raise NotImplementedError, 'Subclasses must implement as_json method'
  end

  def render_ngsi(json)
    if @ngsiv2
      JsonldHelper.to_ngsi_v2(JsonldHelper.to_non_normalized(json))
    else
      @normalized ? json : JsonldHelper.to_non_normalized(json)
    end
  end

  def to_json(*_args)
    as_json.to_json
  end
end
