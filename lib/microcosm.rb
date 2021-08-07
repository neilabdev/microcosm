require "microcosm/version"
require_relative "microcosm/cache"
require_relative "microcosm/database"
module Microcosm
  require 'microcosm/railtie' if defined?(Rails)
end
