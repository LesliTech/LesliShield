=begin

Lesli

Copyright (c) 2025, Lesli Technologies, S. A.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see http://www.gnu.org/licenses/.

Lesli · Ruby on Rails SaaS Development Framework.

Made with ♥ by LesliTech
Building a better future, one line of code at a time.

@contact  hello@lesli.tech
@website  https://www.lesli.tech
@license  GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html

// · ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~
// · 
=end

require_relative "lib/lesli_shield/version"

Gem::Specification.new do |spec|
    spec.name        = "lesli_shield"
    spec.version     = LesliShield::VERSION
    spec.platform    = Gem::Platform::RUBY
    spec.license     = "GPL-3.0-or-later"
    spec.authors     = ["The Lesli Development Team"]
    spec.email       = ["hello@lesli.tech"]
    spec.homepage    = "https://www.lesli.dev/"
    spec.summary     = "Users & security management for the Lesli Framework."
    spec.description = <<~DESC
        Provides a complete authentication and authorization solution for The Lesli Framework, 
        including user session management, secure login and logout, role-based access control, 
        and permission handling.
    DESC

    # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
    # to allow pushing to a single host or delete this section to allow pushing to any host.
    # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

    spec.metadata["homepage_uri"]       = spec.homepage
    spec.metadata["changelog_uri"]      = "https://github.com/LesliTech/LesliShield/releases"
    spec.metadata["source_code_uri"]    = "https://github.com/LesliTech/LesliShield"
    spec.metadata["bug_tracker_uri"]    = "https://github.com/LesliTech/LesliShield/issues"
    spec.metadata["documentation_uri"]  = "https://www.lesli.dev/engines/shield/"

    spec.files = Dir.chdir(File.expand_path(__dir__)) do
        Dir["{app,config,db,lib}/**/*", "license", "Rakefile", "readme.md"]
    end

    # Ruby version
    spec.required_ruby_version = ">= 3.2"

    # Lesli core minimum requirements
    spec.add_dependency("lesli", "~> 5.0")

    # Flexible authentication solution for Rails with Warden
    spec.add_dependency("devise", "~> 4.9")
end
