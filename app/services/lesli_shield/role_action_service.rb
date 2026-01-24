module LesliShield
    class RoleActionService < Lesli::ApplicationLesliService 

        def find id
            super(Role::Action.with_deleted.find(id))
        end

        def index role_id

            def clean action 
                {
                    :id => action.id,
                    :role_id => action.role_id,
                    :action_id => action.action_id,
                    :deleted_at => action.deleted_at,
                    :active => action.active
                }
            end

            role_actions = {}

            Role::Action.with_deleted.joins(action: :parent)
            .where(:role_id => role_id)
            .select(
                :id,
                :role_id,
                :deleted_at,
                "parents_lesli_resources.id as controller_id",
                "parents_lesli_resources.label as controller_name",
                "lesli_resources.action as action_name",
                "lesli_resources.id as action_id",
                "case when lesli_shield_role_actions.deleted_at is null then TRUE else FALSE end active"
            ).each do |action|

                unless role_actions.has_key?(action[:controller_name])
                    role_actions[action[:controller_name]] = {
                        list:nil,
                        index: nil,
                        show:nil,
                        create:nil,
                        update:nil,
                        destroy:nil
                    }
                end

                if  action[:action_name] == "list"
                    role_actions[action[:controller_name]][:list] = clean(action)
                end

                if  action[:action_name] == "index"
                    role_actions[action[:controller_name]][:index] = clean(action)
                end

                if  action[:action_name] == "show"
                    role_actions[action[:controller_name]][:show] = clean(action)
                end

                if  action[:action_name] == "create"
                    role_actions[action[:controller_name]][:create] = clean(action)
                end

                if  action[:action_name] == "update"
                    role_actions[action[:controller_name]][:update] = clean(action)
                end

                if  action[:action_name] == "destroy"
                    role_actions[action[:controller_name]][:destroy] = clean(action)
                end
            end

            role_actions
        end

        def add_guest_actions role
            @role = role

            # Adding default system actions for profile descriptor
            [
                { controller: "lesli_admin/profiles", actions: ["show"] },      # enable profile view
                { controller: "lesli/users", actions: ["options", "update"] },  # enable user edition
                { controller: "lesli/abouts", actions: ["show"] },              # system status
                { controller: "lesli/user/sessions", actions: ["index"] }       # session management
            ].each do |controller_action|

                controller_action[:actions].each do |action_name|

                    system_controller_action = Lesli::Resource.actions.joins(:parent)
                    .where("parents_lesli_resources.route = ?", controller_action[:controller])
                    .where("lesli_resources.action = ?", action_name)

                    @role.actions.find_or_create_by(
                        action: system_controller_action.first
                    )
                end
            end
        end

        def add_owner_actions role
            @role = role

            # Adding default system actions for profile descriptor
            actions = Lesli::Resource.actions

            actions.each do |action|
                @role.actions.find_or_create_by(action: action)
            end
        end
    end
end
