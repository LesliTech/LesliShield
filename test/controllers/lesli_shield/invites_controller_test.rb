require "test_helper"

module LesliShield
    class InvitesControllerTest < ActionController::TestCase
        tests InvitesController

        test "loads invitations only from the current account" do
            current_context = insert_account_context("current")
            another_context = insert_account_context("another")
            current_invite = insert_invite(
                current_context,
                email: "current-invite@example.com"
            )
            another_invite = insert_invite(
                another_context,
                email: "another-invite@example.com"
            )

            with_current_user(current_context.fetch(:user)) do
                @controller.params = ActionController::Parameters.new(
                    id: current_invite.id
                )
                @controller.send(:set_invite)

                assert_equal current_invite, @controller.instance_variable_get(:@invite)

                @controller.params = ActionController::Parameters.new(
                    id: another_invite.id
                )

                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:set_invite)
                end
            end
        end

        test "lists only invitations from the current account" do
            current_context = insert_account_context("list-current")
            another_context = insert_account_context("list-another")
            current_invite = insert_invite(
                current_context,
                email: "listed@example.com"
            )
            insert_invite(
                another_context,
                email: "hidden@example.com"
            )

            service = InviteService.new(
                current_context.fetch(:user),
                pagination: { page: 1, perPage: 20 }
            )

            assert_equal [current_invite.id], service.index(nil).ids
        end

        test "ignores lifecycle attributes submitted by the browser" do
            @controller.params = ActionController::Parameters.new(
                invite: {
                    email: "person@example.com",
                    role_id: "12",
                    status: "accepted",
                    accepted_user_id: "34",
                    accepted_at: Time.current,
                    cancelled_at: Time.current,
                    invited_by_id: "56"
                }
            )

            permitted_attributes = @controller.send(:invite_params)

            assert_equal %w[email role_id], permitted_attributes.keys.sort
            refute permitted_attributes.key?(:status)
            refute permitted_attributes.key?(:accepted_user_id)
            refute permitted_attributes.key?(:invited_by_id)
        end

        test "accepts only active roles assignable by the current user" do
            current_context = insert_account_context("roles-current")
            another_context = insert_account_context("roles-another")
            current_role = insert_role(
                current_context,
                name: "current-role",
                permission_level: 100
            )
            assign_role(current_context.fetch(:user), current_role)

            # An inactive role must not increase the user's effective level.
            inactive_elevated_role = insert_role(
                current_context,
                name: "inactive-elevated",
                permission_level: 1_000,
                active: false
            )
            assign_role(current_context.fetch(:user), inactive_elevated_role)

            assignable_role = insert_role(
                current_context,
                name: "assignable",
                permission_level: 50
            )
            elevated_role = insert_role(
                current_context,
                name: "elevated",
                permission_level: 101
            )
            inactive_role = insert_role(
                current_context,
                name: "inactive",
                permission_level: 10,
                active: false
            )
            foreign_role = insert_role(
                another_context,
                name: "foreign",
                permission_level: 10
            )
            current_user = current_context.fetch(:user)

            assert_equal 100, current_user.max_level_permission
            assert current_user.can_assign_role?(assignable_role)
            refute current_user.can_assign_role?(elevated_role)
            refute current_user.can_assign_role?(inactive_role)
            refute current_user.can_assign_role?(foreign_role)

            with_current_user(current_user) do
                assert_equal assignable_role,
                    @controller.send(:assignable_role!, assignable_role.id)

                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:assignable_role!, elevated_role.id)
                end

                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:assignable_role!, inactive_role.id)
                end

                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:assignable_role!, foreign_role.id)
                end
            end
        end

        test "registers independent resend and cancel routes" do
            actions = LesliShield::Engine.routes.routes.filter_map do |route|
                defaults = route.defaults
                next unless defaults[:controller] == "lesli_shield/invites"

                defaults[:action]
            end

            assert_includes actions, "resend"
            assert_includes actions, "cancel"
        end

        test "exposes resend and cancel in the role privilege matrix" do
            context = insert_account_context("privilege-matrix")
            role = insert_role(
                context,
                name: "privilege-manager",
                permission_level: 100
            )
            timestamp = Time.current
            controller_resource_id = Lesli::Resource.insert_all!([{
                engine: "shield",
                identifier: "LesliShield::Invites",
                label: "Invites",
                route: "lesli_shield/invites",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            %w[resend cancel].each do |action_name|
                action_id = Lesli::Resource.insert_all!([{
                    action: action_name,
                    identifier: action_name,
                    label: action_name.humanize,
                    parent_id: controller_resource_id,
                    created_at: timestamp,
                    updated_at: timestamp
                }]).rows.first.first

                Role::Action.insert_all!([{
                    role_id: role.id,
                    action_id: action_id,
                    created_at: timestamp,
                    updated_at: timestamp
                }])
            end

            privilege_matrix = RoleActionService
                .new(context.fetch(:user))
                .index(role.id)
            invite_actions = privilege_matrix.fetch("lesli_shield/invites")

            assert invite_actions.fetch(:resend)
            assert invite_actions.fetch(:cancel)
        end

        private

        def insert_account_context(identifier)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "#{identifier}-account@example.com",
                name: "Account #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            shield_account_id = LesliShield::Account.insert_all!([{
                account_id: account_id,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            user_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "UID-#{identifier}",
                email: "#{identifier}-owner@example.com",
                encrypted_password: "",
                active: true,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            {
                account: Lesli::Account.find(account_id),
                shield_account: LesliShield::Account.find(shield_account_id),
                user: Lesli::User.find(user_id)
            }
        end

        def insert_invite(context, email:)
            timestamp = Time.current
            invite_id = Invite.insert_all!([{
                account_id: context.fetch(:shield_account).id,
                invited_by_id: context.fetch(:user).id,
                email: email,
                status: Invite.statuses.fetch("pending"),
                expires_at: 1.day.from_now,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Invite.find(invite_id)
        end

        def insert_role(context, name:, permission_level:, active: true)
            timestamp = Time.current
            role_id = Lesli::Role.insert_all!([{
                account_id: context.fetch(:account).id,
                name: name,
                code: name,
                permission_level: permission_level,
                active: active,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Lesli::Role.find(role_id)
        end

        def assign_role(user, role)
            timestamp = Time.current
            LesliShield::User::Role.insert_all!([{
                user_id: user.id,
                role_id: role.id,
                created_at: timestamp,
                updated_at: timestamp
            }])
        end

        def with_current_user(user)
            controller_singleton = @controller.singleton_class
            method_was_defined = controller_singleton
                .instance_methods(false)
                .include?(:current_user)
            original_method = controller_singleton.instance_method(:current_user) if method_was_defined

            controller_singleton.define_method(:current_user) { user }
            yield
        ensure
            controller_singleton.remove_method(:current_user)
            if method_was_defined
                controller_singleton.define_method(:current_user, original_method)
            end
        end
    end
end
