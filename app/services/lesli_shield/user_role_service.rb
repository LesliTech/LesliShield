module LesliShield
    class UserRoleService
        def initialize(current_user, user)
            @current_user = current_user
            @user = user
        end

        def index
            @user.user_roles.includes(:role).order(:id)
        end

        def list
            @current_user.account.roles.where(active: true)
                .where(permission_level: ..@current_user.max_level_permission)
                .where.not(id: @user.roles.select(:id)).order(:name, :id)
        end

        def create(role_id)
            role = @current_user.account.roles.find(role_id)
            raise ActiveRecord::RecordNotFound unless @current_user.can_assign_role?(role)

            @user.user_roles.find_or_create_by!(role: role)
        end

        def destroy(id)
            assignment = @user.user_roles.includes(:role).find(id)
            # Inactive roles can still be removed within the administrator's level.
            role = assignment.role
            unless role.account_id == @current_user.account_id &&
                role.permission_level.to_i <= @current_user.max_level_permission
                raise ActiveRecord::RecordNotFound
            end

            assignment.destroy!
        end
    end
end
