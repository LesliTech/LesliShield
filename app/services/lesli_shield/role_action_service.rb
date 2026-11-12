# frozen_string_literal: true

module LesliShield
    # Assigns the initial permission selections required by system roles.
    class RoleActionService < Lesli::ApplicationLesliService
        GUEST_PERMISSIONS = {
            "lesli/users" => %w[update],
            "lesli/abouts" => %w[show],
            "lesli/user/sessions" => %w[index],
            "lesli_admin/profiles" => %w[show]
        }.freeze

        def add_guest_actions(role)
            actions = GUEST_PERMISSIONS.flat_map do |controller, action_names|
                action_names.filter_map do |action_name|
                    find_catalog_action(controller, action_name)
                end
            end

            assign_actions(role, actions)
        end

        def add_owner_actions(role)
            assign_actions(role, active_catalog.to_a)
        end

        private

        def active_catalog
            Lesli::Resource.actions.joins(:parent)
        end

        def find_catalog_action(controller, action_name)
            active_catalog.find_by(
                parents_lesli_resources: { route: controller },
                action: action_name
            )
        end

        def assign_actions(role, actions)
            timestamp = Time.current
            records = actions.map do |action|
                {
                    role_id: role.id,
                    action_id: action.id,
                    deleted_at: nil,
                    created_at: timestamp,
                    updated_at: timestamp
                }
            end
            return role if records.empty?

            Role::Action.upsert_all(
                records,
                unique_by: :index_role_actions_on_role_and_action
            )
            role
        end
    end
end
