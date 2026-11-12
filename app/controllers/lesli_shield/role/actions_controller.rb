# frozen_string_literal: true

module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role

        def index
            load_permission_matrix
        end

        def update
            role_permission_service.apply!(
                role: @role,
                action_ids: permitted_action_ids
            )
            success(I18n.t("lesli_shield.roles.permissions.saved"))
            respond_with_lesli(
                turbo: stream_redirection(role_actions_path(@role)),
                json: { role_id: @role.id },
                redirect: role_actions_path(@role),
                status: :see_other
            )
        rescue RolePermissionService::Error => exception
            load_permission_matrix
            respond_with_lesli(
                turbo: stream_notification_danger(exception.message),
                json: { message: exception.message },
                html: "index",
                status: :unprocessable_content
            )
        end

        private

        def set_role
            @role = role_service.find!(params[:role_id], manageable: true)
        end

        def role_service
            @role_service ||= RoleService.new(current_user)
        end

        def role_permission_service
            @role_permission_service ||= RolePermissionService.new(current_user)
        end

        def permitted_action_ids
            return [] unless params.key?(:action_ids)

            unless params[:action_ids].is_a?(Array)
                raise ActionController::BadRequest, "action_ids must be an array"
            end

            params.permit(action_ids: []).fetch(:action_ids)
        end

        def load_permission_matrix
            @permission_matrix = role_permission_service.matrix(@role)
        end
    end
end
