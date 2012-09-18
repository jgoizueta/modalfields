# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "modalfields"
  s.version = "1.4.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Javier Goizueta"]
  s.date = "2012-09-18"
  s.description = "ModelFields is a Rails plugin that adds fields declarations to your models."
  s.email = "jgoizueta@gmail.com"
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc",
    "TODO"
  ]
  s.files = [
    ".document",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "TODO",
    "VERSION",
    "lib/modalfields.rb",
    "lib/modalfields/modalfields.rb",
    "lib/modalfields/standardfields.rb",
    "lib/modalfields/tasks.rb",
    "lib/tasks/check.rake",
    "lib/tasks/csv.rake",
    "lib/tasks/migrate.rake",
    "lib/tasks/migration.rake",
    "lib/tasks/report.rake",
    "lib/tasks/update.rake",
    "modalfields.gemspec",
    "test/create_database.rb",
    "test/database.yml",
    "test/helper.rb",
    "test/model_cases/bare/after/author.rb",
    "test/model_cases/bare/after/book.rb",
    "test/model_cases/bare/before/author.rb",
    "test/model_cases/bare/before/book.rb",
    "test/model_cases/clean/after/author.rb",
    "test/model_cases/clean/after/book.rb",
    "test/model_cases/clean/before/author.rb",
    "test/model_cases/clean/before/book.rb",
    "test/model_cases/dirty/after/author.rb",
    "test/model_cases/dirty/after/book.rb",
    "test/model_cases/dirty/before/author.rb",
    "test/model_cases/dirty/before/book.rb",
    "test/schema.rb",
    "test/test_diff.rb",
    "test/test_update.rb"
  ]
  s.homepage = "http://github.com/jgoizueta/modalfields"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.23"
  s.summary = "Model annotator with Ruby (Hobo-like) syntax and hooks."

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<modalsettings>, [">= 0"])
      s.add_runtime_dependency(%q<activesupport>, [">= 2.3.5"])
      s.add_runtime_dependency(%q<activerecord>, [">= 2.3.5"])
      s.add_development_dependency(%q<shoulda>, [">= 0"])
      s.add_development_dependency(%q<rdoc>, ["~> 3.12"])
      s.add_development_dependency(%q<bundler>, ["~> 1"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_development_dependency(%q<sqlite3>, [">= 0"])
      s.add_development_dependency(%q<pg>, [">= 0"])
      s.add_runtime_dependency(%q<rails>, [">= 2.3.0"])
    else
      s.add_dependency(%q<modalsettings>, [">= 0"])
      s.add_dependency(%q<activesupport>, [">= 2.3.5"])
      s.add_dependency(%q<activerecord>, [">= 2.3.5"])
      s.add_dependency(%q<shoulda>, [">= 0"])
      s.add_dependency(%q<rdoc>, ["~> 3.12"])
      s.add_dependency(%q<bundler>, ["~> 1"])
      s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
      s.add_dependency(%q<sqlite3>, [">= 0"])
      s.add_dependency(%q<pg>, [">= 0"])
      s.add_dependency(%q<rails>, [">= 2.3.0"])
    end
  else
    s.add_dependency(%q<modalsettings>, [">= 0"])
    s.add_dependency(%q<activesupport>, [">= 2.3.5"])
    s.add_dependency(%q<activerecord>, [">= 2.3.5"])
    s.add_dependency(%q<shoulda>, [">= 0"])
    s.add_dependency(%q<rdoc>, ["~> 3.12"])
    s.add_dependency(%q<bundler>, ["~> 1"])
    s.add_dependency(%q<jeweler>, ["~> 1.8.3"])
    s.add_dependency(%q<sqlite3>, [">= 0"])
    s.add_dependency(%q<pg>, [">= 0"])
    s.add_dependency(%q<rails>, [">= 2.3.0"])
  end
end

