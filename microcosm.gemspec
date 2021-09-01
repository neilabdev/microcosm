require_relative 'lib/microcosm/version'

Gem::Specification.new do |s|
  s.name          = "microcosm"
  s.version       = Microcosm::VERSION
  s.authors       = ["James Whitfield"]
  s.email         = ["ghost@neilab.com"]

  s.summary       = "Permits extracting the minimum records necessary from production to create functional database"
  s.description   = "Allows extracting the minimum records necessary from production to create functional database by downloading a limited set of associated records using introspection and specified limits"
  s.homepage      = "http://github.com/neilabdev/microcosm"
  s.license       = "MIT"
  s.required_ruby_version = ">= 2.4.0"

  s.metadata["homepage_uri"] = s.homepage
  s.metadata["source_code_uri"] = s.homepage
  s.metadata["changelog_uri"] = "http://github.com/neilabdev/microcosm/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  s.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'activesupport', '>= 5.0'
  s.add_dependency 'actionpack', '>= 5.0'
  s.add_dependency 'activemodel', '>= 5.0'
  s.add_dependency "railties", ">= 4.1.0"
  s.add_dependency 'activerecord-import'
  s.add_dependency "scenic", ">= 1.5.1" # TODO:: Add to specific postgres gem
end
