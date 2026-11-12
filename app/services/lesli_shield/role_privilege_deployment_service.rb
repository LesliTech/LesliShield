# frozen_string_literal: true

module LesliShield
    # Compiles a role's selected actions into its effective privilege cache.
    # The compilation and its audit event are one atomic operation.
    class RolePrivilegeDeploymentService
        def initialize(actor)
            @actor = actor
            @role_service = RoleService.new(actor)
        end

        def deploy!(role_or_id)
            role = manageable_role!(role_or_id)

            role.with_lock do
                # Revalidate after waiting for the lock because the actor's
                # account or permission boundary may have changed.
                manageable_role!(role.id)
                timestamp = Time.current
                previous_permissions = role.privileges
                    .where(active: true)
                    .distinct
                    .order(:controller, :action)
                    .pluck(:controller, :action)

                deployed_permissions = RolePrivilegeService.new.rebuild!(
                    role,
                    timestamp: timestamp
                )
                role.update_columns(
                    deployed_at: timestamp,
                    updated_at: timestamp
                )
                RoleAudit.record!(
                    :role_privileges_deployed,
                    role: role,
                    actor: actor,
                    source: self.class,
                    details: {
                        permissions_added: permission_details(deployed_permissions - previous_permissions),
                        permissions_removed: permission_details(previous_permissions - deployed_permissions),
                        affected_users_count: affected_users_count(role)
                    }
                )
            end

            role
        end

        private

        attr_reader :actor, :role_service

        # Store controller/action identities, not cache row IDs: a rebuild
        # replaces those rows, and catalog resources may later be deleted.
        def permission_details(pairs)
            pairs.map do |controller, action|
                { controller: controller, action: action }
            end
        end

        # Count potential impact without storing user lists. Inactive roles
        # and inactive/deleted users do not contribute to authorization.
        def affected_users_count(role)
            return 0 unless role.active?

            User::Role.joins(:user)
                .where(role_id: role.id)
                .where(lesli_users: { account_id: role.account_id, active: true })
                .distinct
                .count(:user_id)
        end

        def manageable_role!(role_or_id)
            role_id = role_or_id.respond_to?(:id) ? role_or_id.id : role_or_id
            role_service.find!(role_id, manageable: true)
        end
    end
end
