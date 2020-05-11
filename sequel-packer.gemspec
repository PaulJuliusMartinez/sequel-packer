require_relative 'lib/sequel/packer/version'

Gem::Specification.new do |spec|
  spec.name          = "sequel-packer"
  spec.version       = Sequel::Packer::VERSION
  spec.authors       = ["Paul Julius Martinez"]
  spec.email         = ["pauljuliusmartinez@gmail.com"]

  spec.summary       = <<~SUMMARY
    A serialization library for use with the Sequel ORM.
  SUMMARY
  spec.description   = <<~DESCRIPTION
    sequel-packer is a flexible declarative DSL-based library for efficiently
    serializing Sequel models and their associations to JSON.
  DESCRIPTION
  spec.homepage      = "https://github.com/PaulJuliusMartinez/sequel-packer"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/PaulJuliusMartinez/sequel-packer"
  spec.metadata["changelog_uri"] = "https://github.com/PaulJuliusMartinez/sequel-packer/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "sequel", "~> 5.0"

  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "awesome_print"
  spec.add_development_dependency "sqlite3"
end
