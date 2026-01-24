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

namespace :lesli_shield do

    desc "Syncing privileges for all the available roles"
    task :privileges => :environment do |task, args|
        lesli_shield_privileges()
    end

    # Drop, build, migrate & seed database (development only)
    def lesli_shield_privileges

        Lesli::Role.all.each do |role|
            L2.info("LesliShield: Syncing privileges for #{role.name} role.")
            LesliShield::RolePrivilegeService.new(nil).synchronize(role)
        end
    end
end
