require 'rails/railtie'

module Microcosm
  class Railtie < Rails::Railtie
    railtie_name :microcosm

    rake_tasks { Dir[File.join(File.dirname(__FILE__), 'tasks/*.rake')].each { |f| load f } }
  end
end