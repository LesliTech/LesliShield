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

require "devise"

module LesliShield
    class Engine < ::Rails::Engine
        isolate_namespace LesliShield

        # Rails 8 defers route loading in local environments. Load the main
        # routes before the application starts accepting requests so Warden is
        # initialized with the Devise mapping created by Shield's router.
        config.after_initialize do |app|
            app.routes_reloader.execute_unless_loaded
        end

        initializer "lesli_shield.authentication_routes" do
            if Lesli::Router.respond_to?(:authentication_router=)
                Lesli::Router.authentication_router = LesliShield::Router
            end
        end

        config.to_prepare do
            unless Lesli::User < LesliShield::UserAuthentication
                Lesli::User.include(LesliShield::UserAuthentication)
            end

            unless Lesli::User < LesliShield::UserSecurity
                Lesli::User.include(LesliShield::UserSecurity)
            end

            # Compatibility for core versions whose Devise base controller did
            # not explicitly expose Lesli helpers to isolated engines.
            devise_controller = Lesli::ApplicationDeviseController
            core_helper_modules = [Lesli::SystemHelper, Lesli::HtmlHelper]

            # The controller and layout live in Lesli, while Shield owns the
            # specialized Devise forms. Put those forms before Devise's bundled
            # defaults in the lookup order whenever Shield is installed.
            shield_views = LesliShield::Engine.root.join("app", "views")
            unless devise_controller.view_paths.first&.to_path == shield_views.to_s
                devise_controller.prepend_view_path(shield_views)
            end

            core_helper_modules.each do |helper_module|
                next if devise_controller._helpers < helper_module

                devise_controller.helper(helper_module)
            end
        end

        initializer :lesli_shield do |app|
            
            # register assets manifest
            config.assets.precompile += %w[lesli_shield_manifest.js]

            # register engine migrations path
            unless app.root.to_s.match root.to_s
                config.paths["db/migrate"].expanded.each do |expanded_path|
                    app.config.paths["db/migrate"] << expanded_path
                end
            end
        end
    end
end
