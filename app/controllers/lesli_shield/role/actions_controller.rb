# frozen_string_literal: true

module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role

        def index
            load_permission_matrix
        end

        def create
            persist_permission!(
                action_id: params.require(:action_id),
                enabled: true
            )
        end

        def destroy
            persist_permission!(action_id: params[:id], enabled: false)
        end

        private

        def persist_permission!(action_id:, enabled:)
            role_permission_service.set!(
                role: @role,
                action_id: action_id,
                enabled: enabled
            )
            @role.reload
            load_permission_matrix
            respond_with_lesli(
                turbo: [
                    stream_notification_success(
                        I18n.t("lesli_shield.roles.permissions.update_success")
                    ),
                    turbo_stream.replace(
                        "shield-role-actions-form",
                        partial: "lesli_shield/role/actions/form"
                    ),
                    turbo_stream.replace(
                        "role-permission-deployment-status",
                        partial: "lesli_shield/role/actions/deployment_status"
                    )
                ],
                json: {
                    role_id: @role.id,
                    action_id: action_id.to_i,
                    enabled: enabled
                },
                redirect: role_actions_path(@role, search: search_term.presence)
            )
        rescue RolePermissionService::Error => exception
            respond_with_lesli(
                turbo: stream_notification_danger(exception.message),
                json: { message: exception.message },
                redirect: role_actions_path(@role, search: search_term.presence),
                status: :unprocessable_content
            )
        end

        def set_role
            @role = role_service.find!(params[:role_id], manageable: true)
        end

        def role_service
            @role_service ||= RoleService.new(current_user)
        end

        def role_permission_service
            @role_permission_service ||= RolePermissionService.new(current_user)
        end

        def load_permission_matrix
            @permission_matrix = role_permission_service.matrix(@role)
            @search = search_term
            return if @search.blank?

            @permission_matrix = filter_permission_matrix(@permission_matrix, @search)
        end

        def filter_permission_matrix(matrix, search)
            query = search.downcase

            matrix.filter_map do |engine|
                resources = engine[:resources].filter_map do |resource|
                    actions = resource[:actions].select do |action|
                        permission_matches?(engine, resource, action, query)
                    end
                    resource.merge(actions: actions) if actions.any?
                end

                engine.merge(resources: resources) if resources.any?
            end
        end

        def permission_matches?(engine, resource, action, query)
            [
                engine[:engine],
                engine[:label],
                resource[:identifier],
                resource[:label],
                resource[:route],
                action[:identifier],
                action[:label],
                action[:display_label],
                action[:action]
            ].any? { |value| value.to_s.downcase.include?(query) }
        end

        def search_term
            params[:search].to_s.strip
        end
    end
end
