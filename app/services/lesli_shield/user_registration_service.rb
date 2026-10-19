=begin

Lesli

Copyright (c) 2026, Lesli Technologies, S. A.

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

module LesliShield
    class UserRegistrationService < Lesli::ApplicationLesliService

        def initialize(user)
            super(user)
            self.resource = user
        end

        # Devise owns confirmation. This service performs only the Lesli account
        # provisioning that must happen after Devise accepts the token.
        def provision_account!
            assign_account! if resource.account.blank?
            assign_initial_role! unless resource.user_roles.exists?
            synchronize_role_privileges!

            resource
        end

        private

        def assign_account!
            account = if multiaccount?
                create_owned_account!
            else
                Lesli::Account.first!
            end

            resource.update!(account: account)
        end

        def create_owned_account!
            Lesli::Account.create!(
                user: resource,
                name: "Lesli",
                email: resource.email,
                status: :active
            )
        end

        def assign_initial_role!
            role = resource.account.roles.find_by!(name: initial_role_name)
            resource.user_roles.create!(role: role)
        end

        def initial_role_name
            return "owner" if multiaccount?

            Lesli.config.shield.dig(:default_role).presence || "guest"
        end

        def synchronize_role_privileges!
            resource.roles.find_each do |role|
                LesliShield::RolePrivilegeService.new(nil).synchronize(role)
            end
        end

        # Read the setting at execution time. Applications and tests can change
        # Lesli configuration after this service class has been loaded.
        def multiaccount?
            Lesli.config.security.dig(:allow_multiaccount) == true
        end
    end
end
