# frozen_string_literal: true

module LesliShield
    class RolesController < ApplicationController
        before_action :set_visible_role, only: %i[show]
        before_action :set_manageable_role, only: %i[edit update destroy deploy]

        def index
            @roles = respond_with_pagination(
                role_service.list(params)
            )
        end

        def show; end

        def new
            @role = current_user.account.roles.new(active: true)
        end

        def edit; end

        def create
            @role = role_service.create!(role_params)
            success(I18n.t("lesli_shield.roles.created_successfully"))
            respond_with_lesli(
                json: @role,
                redirect: role_path(@role)
            )
        rescue RoleService::Error => exception
            respond_with_role_error(exception, template: "new")
        end

        def update
            @role = role_service.update!(@role, role_params)
            respond_with_lesli(
                turbo: stream_notification_success(
                    I18n.t("lesli_shield.roles.updated_successfully")
                ),
                json: @role,
                redirect: role_path(@role)
            )
        rescue RoleService::Error => exception
            respond_with_role_error(exception, template: "show")
        end

        def destroy
            role_service.destroy!(@role)
            success(I18n.t("lesli_shield.roles.destroyed_successfully"))
            respond_with_lesli(redirect: roles_path)
        rescue RoleService::Error => exception
            respond_with_role_error(exception, template: "show")
        end

        def deploy
            RolePrivilegeDeploymentService.new(current_user).deploy!(@role)
            success(I18n.t("lesli_shield.roles.permissions.deployed"))
            respond_with_lesli(
                turbo: stream_redirection(role_actions_path(@role)),
                json: { role_id: @role.id },
                redirect: role_actions_path(@role),
                status: :see_other
            )
        end

        private

        def role_service
            @role_service ||= RoleService.new(current_user, query)
        end

        def set_visible_role
            @role = role_service.find!(params[:id])
        end

        def set_manageable_role
            @role = role_service.find!(params[:id], manageable: true)
        end

        def role_params
            params.require(:role).permit(
                :name,
                :active,
                :description,
                :path_default,
                :permission_level
            )
        end

        def respond_with_role_error(exception, template:)
            @role = exception.record || @role
            respond_with_lesli(
                turbo: stream_notification_danger(exception.message),
                json: {
                    message: exception.message,
                    errors: @role&.errors&.to_hash
                },
                html: template,
                status: :unprocessable_content
            )
        end
    end
end
