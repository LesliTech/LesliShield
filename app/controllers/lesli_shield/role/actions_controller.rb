module LesliShield
    class Role::ActionsController < ApplicationController
        #before_action :set_dashboard_component, only: %i[ show edit update destroy ]

        def update
            success("Role privileges updated successfully!")
            respond_to do |format|
                format.turbo_stream
                format.html { redirect_to @role }
            end
        end
    end
end
