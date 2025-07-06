module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role_action, only: %i[update destroy ]

        def update
            # check saved
            if @role_action.result.recover
                success("Role privileges added successfully!")
                respond_to do |format|
                    format.turbo_stream
                    render turbo_stream: turbo_stream.replace("application-lesli-notifications", partial: "lesli/partials/application-lesli-notifications")
                    #format.html { redirect_to role_path(@role_action.role_id) }
                end
            else 
                respond_with_error(@user.errors)
            end
        end

        def destroy
            # check saved
            if @role_action.result.destroy
                success("Role privileges removed successfully!")
                respond_to do |format|
                    format.turbo_stream
                    #format.html { redirect_to role_path(@role_action.role_id) }
                end
            else 
                respond_with_error(@user.errors)
            end
        end

        private

        # Use callbacks to share common setup or constraints between actions.
        def set_role_action
            @role_action = Lesli::Role::ActionService.new(current_user).find(params[:id])
        end

        def role_action_params
            params.require(:role_action).permit(
                :role_id
            )
        end
    end
end
