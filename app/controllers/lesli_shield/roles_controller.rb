# frozen_string_literal: true

module LesliShield
    class RolesController < ApplicationController
        before_action :set_visible_role, only: %i[show]
        before_action :set_manageable_role, only: %i[edit update destroy deploy]

        def index
            @roles = respond_with_pagination(
                Lesli::RoleService.new(current_user, query).index
            )
        end

        def show; end

        def new
            @role = current_user.account.roles.new(active: true)
        end

        def edit; end

        def create
            @role = current_user.account.roles.new(role_params)
            ensure_manageable!(@role)

            if @role.save
                respond_with_successful(@role)
            else
                respond_with_error(@role.errors.full_messages.to_sentence)
            end
        end

        def update
            @role.assign_attributes(role_params)
            ensure_manageable!(@role)

            if @role.save
                respond_with_lesli(
                    turbo: stream_notification_success("Role updated successfully!")
                )
            else
                respond_with_lesli(
                    turbo: stream_notification_danger(
                        @role.errors.full_messages.to_sentence
                    )
                )
            end
        end

        def destroy
            if @role.assigned?
                return respond_with_error(
                    I18n.t("core.roles.messages_danger_users_assigned_validation")
                )
            end

            raise ActiveRecord::RecordNotFound unless @role.deletable_by?(current_user)

            if @role.destroy
                respond_with_successful
            else
                respond_with_error(@role.errors.full_messages.to_sentence)
            end
        end

        # This endpoint remains temporarily for the current permission UI. The
        # bulk permission service will replace it with apply-on-save behavior.
        def deploy
            RolePrivilegeDeploymentService.new(current_user).deploy!(@role)
            respond_with_lesli(
                turbo: stream_notification_success("Role privileges applied successfully!")
            )
        end

        private

        def visible_roles
            current_user.account.roles.where(
                permission_level: ..current_user.max_level_permission
            )
        end

        def set_visible_role
            @role = visible_roles.find(params[:id])
        end

        def set_manageable_role
            @role = visible_roles.find(params[:id])
            ensure_manageable!(@role)
        end

        def ensure_manageable!(role)
            return if role.manageable_by?(current_user)

            raise ActiveRecord::RecordNotFound
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
    end
end
