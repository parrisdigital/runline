#!/usr/bin/env ruby
# frozen_string_literal: true

build_number = ARGV.fetch(0, "").strip

unless build_number.match?(/\A[1-9][0-9]*\z/)
  warn "Usage: ruby Tools/set_build_number.rb BUILD_NUMBER"
  warn "BUILD_NUMBER must be a positive integer."
  exit 2
end

project_path = File.expand_path("../project.yml", __dir__)
contents = File.read(project_path)

pattern = /^(\s*CURRENT_PROJECT_VERSION:\s*)"?[0-9]+"?$/

unless contents.match?(pattern)
  warn "Could not find CURRENT_PROJECT_VERSION in #{project_path}."
  exit 1
end

updated = contents.sub(pattern, "\\1\"#{build_number}\"")
File.write(project_path, updated)
warn "Set CURRENT_PROJECT_VERSION to #{build_number} in project.yml."
