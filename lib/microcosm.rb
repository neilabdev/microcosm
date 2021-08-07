require "microcosm/version"
require_relative "microcosm/util"
require_relative "microcosm/cache"
require_relative "microcosm/database"

module Microcosm

end

require 'microcosm/railtie'  if defined?(Rails::Railtie)