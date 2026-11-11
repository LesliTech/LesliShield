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

            records = Role::Action.with_deleted.joins(action: :parent)
            .where(:role_id => role_id)
            .order('parents_lesli_resources.route')
            .select(
                :id,
                :role_id,
                :deleted_at,
                "parents_lesli_resources.id as controller_id",
                "parents_lesli_resources.label as controller_name",
                "parents_lesli_resources.route as controller_route",
                "lesli_resources.action as action_name",
                "lesli_resources.id as action_id",
                "case when lesli_shield_role_actions.deleted_at is null then TRUE else FALSE end active"
            ).to_a

            standard_action_order = %w[index show new edit create update destroy]
            registered_actions = records.map { |action| action[:action_name] }.uniq
            action_order = standard_action_order.select do |action_name|
                registered_actions.include?(action_name)
            end
            action_order.concat((registered_actions - standard_action_order).sort)
            action_order.map!(&:to_sym)

            role_actions = {}

            records.each do |action|
                controller_actions = role_actions.fetch(
                    action[:controller_route],
                    action_order.index_with(nil)
                )
                controller_actions[action[:action_name].to_sym] = clean(action)
                role_actions[action[:controller_route]] = controller_actions
            end

            role_actions
        end

        def add_guest_actions role

            # Adding default system actions for profile descriptor
            [
                { controller: "lesli/users", actions: ["update"] },        # enable user edition
                { controller: "lesli/abouts", actions: ["show"] },         # system status
                { controller: "lesli/user/sessions", actions: ["index"] }, # session management
                { controller: "lesli_admin/profiles", actions: ["show"] }  # enable profile view
            ].each do |controller_action|

                controller_action[:actions].each do |action_name|

                    system_controller_action = Lesli::Resource.actions.joins(:parent)
                    .where("parents_lesli_resources.route = ?", controller_action[:controller])
                    .where("lesli_resources.action = ?", action_name)

                    role.actions.find_or_create_by(
                        action: system_controller_action.first
                    )
                end
            end
        end

        def add_owner_actions role

            now = Time.current

            # Adding default system actions for profile descriptor
            actions = Lesli::Resource.actions

            records = actions.map do |action|
                {
                    role_id: role.id,
                    action_id: action.id,
                    created_at: now,
                    updated_at: now
                }
            end

            role.actions.upsert_all(records,
                unique_by: :index_role_actions_on_role_and_action
            )
        end
    end
end
