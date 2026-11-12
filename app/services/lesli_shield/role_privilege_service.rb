# frozen_string_literal: true

module LesliShield
    # Builds the effective authorization cache for one role.
    #
    # `Role::Action` is the source of truth: it stores the permissions selected
    # by an administrator. `Role::Privilege` is only a cache used to authorize
    # requests quickly. Rebuilding therefore replaces every cached row instead
    # of trying to update the previous cache incrementally.
    #
    # This service is deliberately unaware of users and authorization policy.
    # RolePrivilegeDeploymentService is responsible for validating the actor,
    # locking the role, updating `deployed_at`, and recording the audit event.
    class RolePrivilegeService
        # Replaces the role's complete privilege cache.
        #
        # Deleted role actions and deleted catalog resources are automatically
        # excluded by the models' default scopes. If the role has no selected
        # actions, the resulting cache is empty.
        #
        # @param role [Lesli::Role] role whose cache will be rebuilt
        # @param timestamp [Time] timestamp shared by every inserted cache row
        # @return [Array<Array<String>>] unique `[controller, action]` pairs
        def rebuild!(role, timestamp: Time.current)
            permission_pairs = selected_permission_pairs(role)

            Role::Privilege.transaction do
                delete_previous_cache!(role)
                insert_cache!(role, permission_pairs, timestamp)
            end

            permission_pairs
        end

        private

        # Different catalog entries may resolve to the same controller/action.
        # The cache stores each effective permission only once.
        def selected_permission_pairs(role)
            role.actions
                .joins(action: :parent)
                .pluck(
                    "parents_lesli_resources.route",
                    "lesli_resources.action"
                )
                .uniq
                .sort
        end

        # Privileges use soft deletion elsewhere. A rebuild needs a physical
        # deletion so stale cache rows cannot survive the deployment.
        def delete_previous_cache!(role)
            Role::Privilege.with_deleted
                .where(role_id: role.id)
                .delete_all!
        end

        # The cache contains granted permissions only. `active: true` is kept
        # because it is part of the authorization query's persisted contract.
        def insert_cache!(role, permission_pairs, timestamp)
            cache_rows = permission_pairs.map do |controller, action|
                {
                    role_id: role.id,
                    controller: controller,
                    action: action,
                    active: true,
                    created_at: timestamp,
                    updated_at: timestamp
                }
            end
            return if cache_rows.empty?

            Role::Privilege.insert_all!(cache_rows)
        end
    end
end
