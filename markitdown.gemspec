# frozen_string_literal: true

require_relative "lib/markitdown/version"

Gem::Specification.new do |spec|
  spec.name = "markitdown"
  spec.version = Markitdown::VERSION
  spec.authors = ["Ali Umair"]
  spec.email = ["aliumair.dev@gmail.com"]

  spec.summary = "Convert documents and images into Markdown for AI ingestion."
  spec.description = "A local Ruby document-to-Markdown converter inspired by Microsoft MarkItDown."
  spec.homepage = "https://github.com/aliumairdev/markitdown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", ">= 0.2"
  spec.add_dependency "json", ">= 2.0"
  spec.add_dependency "nokogiri", ">= 1.15"
  spec.add_dependency "pdf-reader", "~> 2.15"
  spec.add_dependency "rubyzip", "~> 2.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
