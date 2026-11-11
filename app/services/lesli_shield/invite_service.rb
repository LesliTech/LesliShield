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

module LesliShield
    class InviteService < Lesli::ApplicationLesliService
        STATUS_FILTERS = %w[pending accepted cancelled expired].freeze

        def self.status_filter(value)
            value.to_s.presence_in(STATUS_FILTERS)
        end

        def index(params)
            invitations = Invite
                .for_account(current_user.account.shield)
                .includes(:invited_by, :role)

            invitations = filter_by_status(
                invitations,
                self.class.status_filter(params&.[](:status))
            )

            invitations
                .page(query[:pagination][:page])
                .per(query[:pagination][:perPage])
                .order(created_at: :desc)
        end

        private

        def filter_by_status(invitations, status)
            case status
            when "pending"
                invitations.active
            when "expired"
                invitations.expired
            when "accepted", "cancelled"
                invitations.where(status: Invite.statuses.fetch(status))
            else
                invitations
            end
        end
    end
end
