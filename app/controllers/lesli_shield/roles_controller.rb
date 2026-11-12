# frozen_string_literal: true

module LesliShield
    class RolesController < ApplicationController
        before_action :set_visible_role, only: %i[show duplicate]
        before_action :set_manageable_role, only: %i[edit update destroy deploy]

        def index
            @filters = {
                search: params[:search].to_s.strip,
                status: allowed_filter(params[:status], RoleService::STATUS_FILTERS),
                type: allowed_filter(params[:type], RoleService::TYPE_FILTERS)
            }
            @roles = respond_with_pagination(
                role_service.list(@filters)
            )
        end

        def show
            prepare_role_page
        end

        def new
            @role = role_service.build
        end

        def edit
            prepare_role_page
            render :show
        end

        def create
            @role = role_service.create!(role_attributes)
            success(I18n.t("lesli_shield.roles.created_successfully"))
            respond_with_lesli(
                json: @role,
                redirect: role_path(@role)
            )
        rescue RoleService::Error => exception
            respond_with_role_error(exception, template: "new")
        end

        def update
            @role = role_service.update!(@role, role_attributes)
            success(I18n.t("lesli_shield.roles.updated_successfully"))
            respond_with_lesli(
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

        def duplicate
            duplicate = role_service.duplicate!(@role)
            success(
                I18n.t(
                    "lesli_shield.roles.duplicated_successfully",
                    role: duplicate.name
                )
            )
            respond_with_lesli(
                json: duplicate,
                redirect: role_path(duplicate)
            )
        rescue RoleService::Error => exception
            danger(exception.message)
            respond_with_lesli(
                json: { message: exception.message },
                redirect: role_path(@role),
                status: :unprocessable_content
            )
        end

        def deploy
            RolePrivilegeDeploymentService.new(current_user).deploy!(@role)
            success(I18n.t("lesli_shield.roles.permissions.deployed"))
            destination = permission_index_path
            respond_with_lesli(
                turbo: stream_redirection(destination),
                json: { role_id: @role.id },
                redirect: destination,
                status: :see_other
            )
        end

        private

        def role_service
            @role_service ||= RoleService.new(current_user, query)
        end

        def permission_index_path
            options = { search: params[:search].presence }
            if params[:engine_slug].present?
                engine_role_actions_path(@role, engine_slug: params[:engine_slug], **options)
            else
                role_actions_path(@role, **options)
            end
        end

        def set_visible_role
            @role = role_service.find!(params[:id])
        end

        def set_manageable_role
            @role = role_service.find!(params[:id], manageable: true)
        end

        def role_attributes
            params.require(:role).permit(
                :name,
                :active,
                :description,
                :path_default,
                :permission_level
            ).to_h.symbolize_keys
        end

        def allowed_filter(value, options)
            value if options.include?(value)
        end

        def prepare_role_page
            @role_summary = role_service.summary(@role)
        end

        def respond_with_role_error(exception, template:)
            @role = exception.record || @role
            prepare_role_page if @role.persisted?
            respond_with_lesli(
                turbo: [
                    turbo_stream.replace(
                        "role-form",
                        partial: "lesli_shield/roles/form"
                    ),
                    stream_notification_danger(exception.message)
                ],
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
