module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role, only: %i[index update destroy]
        before_action :set_role_action, only: %i[update destroy]

        def index 
            @role_actions = Lesli::RoleActionService.new(current_user, query).index(@role.id)
        end

        def update
            if @role_action.result.recover
                @role_actions = Lesli::RoleActionService.new(current_user, query).index(@role.id)
                respond_with_lesli(
                    :turbo => [
                        stream_notification_success("Role privileges added successfully!"),
                        turbo_stream.replace('shield-role-actions-form', partial: 'lesli_shield/role/actions/form')
                    ]
                )
            else 
                respond_with_lesli(
                    :turbo => stream_notification_danger(@role_action.errors_as_sentence)
                )
            end
        end

        def destroy
            if @role_action.result.delete
                @role_actions = Lesli::RoleActionService.new(current_user, query).index(@role.id)
                respond_with_lesli(
                    :turbo => [
                        stream_notification_warning("Role privileges removed successfully!"),
                        turbo_stream.replace('shield-role-actions-form', partial: 'lesli_shield/role/actions/form')
                    ]
                )
            else 
                respond_with_lesli(
                    :turbo => stream_notification_danger(@role_action.errors_as_sentence)
                )
            end
        end

        private

        def set_role
            @role = current_user.account.roles.find(params[:role_id])
        end 

        def set_role_action
            @role_action = Lesli::RoleActionService.new(current_user).find(params[:id])
        end

        def role_action_params
            params.require(:role_action).permit(
                :role_id
            )
        end
    end
end
