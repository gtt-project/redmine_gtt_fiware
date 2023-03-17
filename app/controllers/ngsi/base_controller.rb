class Ngsi::BaseController < ApplicationController

  def to_boolean(str)
    str.to_s.downcase == "true"
  end

end
