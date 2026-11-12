# frozen_string_literal: true

module LesliShield
    class Role::ActionsController < ApplicationController
        before_action :set_role
        before_action :set_role_action, only: %i[update destroy]

        def index
            load_role_actions
        end

        def update
            if @role_action.recover
                load_role_actions
                respond_with_lesli(
                    turbo: [
                        stream_notification_success("Role privilege added successfully!"),
                        turbo_stream.replace(
                            "shield-role-actions-form",
                            partial: "lesli_shield/role/actions/form"
                        )
                    ]
                )
            else
                respond_with_lesli(
                    turbo: stream_notification_danger(
                        @role_action.errors.full_messages.to_sentence
                    )
                )
            end
        end

        def destroy
            if @role_action.delete
                load_role_actions
                respond_with_lesli(
                    turbo: [
                        stream_notification_warning("Role privilege removed successfully!"),
                        turbo_stream.replace(
                            "shield-role-actions-form",
                            partial: "lesli_shield/role/actions/form"
                        )
                    ]
                )
            else
                respond_with_lesli(
                    turbo: stream_notification_danger(
                        @role_action.errors.full_messages.to_sentence
                    )
                )
            end
        end

        private

        def set_role
            @role = current_user.account.roles
                .where(permission_level: ..current_user.max_level_permission)
                .find(params[:role_id])

            raise ActiveRecord::RecordNotFound unless @role.manageable_by?(current_user)
        end

        def set_role_action
            @role_action = @role.actions.with_deleted.find(params[:id])
        end

        def load_role_actions
            @role_actions = RoleActionService.new(current_user, query).index(@role.id)
        end
    end
end
