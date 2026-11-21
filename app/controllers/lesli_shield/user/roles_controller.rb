module LesliShield
    class User::RolesController < ApplicationController
        before_action :set_user

        def index
            prepare_roles
        end

        def create
            role_service.create(params.require(:user_role).require(:role_id))
            redirect_to user_roles_path(@user), status: :see_other
        rescue ActiveRecord::RecordInvalid => error
            @role_error = error.record.errors.full_messages.to_sentence
            prepare_roles
            render :index, formats: [:html], status: :unprocessable_entity
        end

        def destroy
            role_service.destroy(params[:id])
            redirect_to user_roles_path(@user), status: :see_other
        end

        private

        def set_user
            @user = current_user.account.users.find(params[:user_id])
        end

        def role_service
            @role_service ||= UserRoleService.new(current_user, @user)
        end

        def prepare_roles
            @user_roles = role_service.index
            @available_roles = role_service.list
        end
    end
end
