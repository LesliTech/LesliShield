# frozen_string_literal: true

module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role
        before_action :set_permission_filters

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
            respond_with_lesli(
                turbo: permission_update_streams,
                json: {
                    role_id: @role.id,
                    action_id: action_id.to_i,
                    enabled: enabled
                },
                redirect: permission_index_path
            )
        rescue RolePermissionService::Error => exception
            respond_with_lesli(
                turbo: stream_notification_danger(exception.message),
                json: { message: exception.message },
                redirect: permission_index_path,
                status: :unprocessable_content
            )
        end

        def set_role
            @role = role_service.find!(params[:role_id], manageable: true)
        end

        def set_permission_filters
            @engine_slug = params[:engine_slug].presence
            @search = params[:search].to_s.strip

            if @engine_slug && !role_permission_service.engine_available?(@engine_slug)
                raise ActiveRecord::RecordNotFound
            end
        end

        # Only Turbo needs refreshed HTML. Redirects and JSON responses do not
        # need to load the permission catalog after saving a single checkbox.
        def permission_update_streams
            return unless request.format.turbo_stream?

            @role.reload
            load_permission_matrix

            [
                stream_notification_success(
                    I18n.t("lesli_shield.roles.permissions.update_success")
                ),
                turbo_stream.replace(
                    "shield-role-permissions",
                    partial: "lesli_shield/role/actions/permissions"
                ),
                turbo_stream.replace(
                    "role-permission-deployment-status",
                    partial: "lesli_shield/role/actions/deployment_status"
                )
            ]
        end

        def role_service
            @role_service ||= RoleService.new(current_user)
        end

        def role_permission_service
            @role_permission_service ||= RolePermissionService.new(current_user)
        end

        def load_permission_matrix
            @permission_matrix = role_permission_service.matrix(@role)
            @permission_engines = @permission_matrix.map do |engine|
                {
                    slug: engine[:engine].tr("_", "-"),
                    label: engine[:label],
                    count: engine[:resources].sum { |resource| resource[:actions].size }
                }
            end
            if @engine_slug
                @permission_matrix = @permission_matrix.select do |engine|
                    engine[:engine].tr("_", "-") == @engine_slug
                end
            end

            if @search.present?
                @permission_matrix = filter_permission_matrix(
                    @permission_matrix,
                    @search
                )
            end
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

        def permission_index_path
            options = { search: @search.presence }
            if @engine_slug
                return engine_role_actions_path(@role, engine_slug: @engine_slug, **options)
            end

            role_actions_path(@role, **options)
        end
    end
end
