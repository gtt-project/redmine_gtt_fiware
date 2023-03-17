# Ngsi::BaseController is a base controller for the NGSI related controllers.
# It inherits from ApplicationController and provides common functionality
# for the derived controllers.
class Ngsi::BaseController < ApplicationController
  before_action :set_normalized

  # Converts a string to a boolean value. Returns true if the string is "true",
  # otherwise returns false.
  #
  # @param str [String] the input string to convert to a boolean value
  # @return [Boolean] true if the input string is "true", otherwise false
  def to_boolean(str)
    str.to_s.downcase == "true"
  end

  private

  # Set the @normalized value based on the "normalized" query parameter or the plugin setting
  def set_normalized
    @normalized = if params.key?(:normalized)
      to_boolean(params[:normalized])
    else
      to_boolean(Setting.plugin_redmine_gtt_fiware['ngsi_ld_format'])
    end
  end
end
