# Top-level require for the devto_analytics library
require 'json'
require 'csv'

require_relative 'devto_analytics/version'
require_relative 'devto_analytics/cli'
require_relative 'devto_analytics/api_client'
require_relative 'devto_analytics/collector'
require_relative 'devto_analytics/formatter'
require_relative 'devto_analytics/server'

module DevtoAnalytics
  class Error < StandardError; end
end
