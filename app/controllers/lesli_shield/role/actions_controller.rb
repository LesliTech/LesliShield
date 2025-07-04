module LesliShield
    class Role::ActionsController < ApplicationController
        #before_action :set_dashboard_component, only: %i[ show edit update destroy ]

        def update
            pp "---   ---   ---   ---   ---   ---   ---   ---"
            pp params[:role_id]
            pp "---   ---   ---   ---   ---   ---   ---   ---"
            success("Role privileges updated successfully!")
            respond_to do |format|
                format.turbo_stream
                format.html { redirect_to @role }
            end
        end

        def role_action_params
            params.require(:role_action).permit(
                :role_id
            )
        end
    end
end
