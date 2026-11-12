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

        test "filters invitations by their effective lifecycle status" do
            context = insert_account_context("status-filters")
            active = insert_invite(
                context,
                email: "active-filter@example.com"
            )
            overdue = insert_invite(
                context,
                email: "overdue-filter@example.com",
                expires_at: 1.minute.ago
            )
            accepted = insert_invite(
                context,
                email: "accepted-filter@example.com",
                status: :accepted
            )
            cancelled = insert_invite(
                context,
                email: "cancelled-filter@example.com",
                status: :cancelled
            )
            service = InviteService.new(
                context.fetch(:user),
                pagination: { page: 1, perPage: 20 }
            )

            assert_equal [active.id], service.index(status: "pending").ids
            assert_equal [overdue.id], service.index(status: "expired").ids
            assert_equal [accepted.id], service.index(status: "accepted").ids
            assert_equal [cancelled.id], service.index(status: "cancelled").ids
        end

        test "shows a pending invitation without editable fields" do
            context = insert_account_context("readonly-show")
            invite = insert_invite(
                context,
                email: "readonly-invite@example.com"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :show, params: { id: invite.id }
            end

            assert_response :success
            assert_select "input[name='invite[email]']", count: 0
            assert_select "form[action='#{cancel_invite_path(invite)}']"
            assert_select "form[action='#{resend_invite_path(invite)}']",
                count: 0
            assert_includes response.body, invite.email
        end

        test "renders the creation form with only invitation fields" do
            context = insert_account_context("new-form")
            owner_role = insert_role(
                context,
                name: "owner-role",
                permission_level: 100
            )
            target_role = insert_role(
                context,
                name: "target-role",
                permission_level: 50
            )
            assign_role(context.fetch(:user), owner_role)

            with_authenticated_request(context.fetch(:user)) do
                get :new
            end

            assert_response :success
            assert_select "input[name='invite[email]'][required]"
            assert_select "input[name='invite[full_name]']"
            assert_select "select[name='invite[role_id]'][required]" do
                assert_select "option[value='#{target_role.id}']"
            end
            assert_select "textarea[name='invite[notes]']"
            assert_select "input[name='invite[telephone]']", count: 0
            assert_select "button[data-turbo-submits-with]", text: I18n.t(
                "lesli_shield.invites.button_create_and_send"
            )
        end

        test "renders creation errors inline" do
            context = insert_account_context("inline-errors")

            with_authenticated_request(context.fetch(:user)) do
                post :create, params: {
                    invite: {
                        email: "person@example.com",
                        role_id: ""
                    }
                }
            end

            assert_response :unprocessable_content
            assert_select ".lesli-form-field.is-danger"
            assert_select ".lesli-form-help.is-danger", text: I18n.t(
                "lesli_shield.invites.role_required"
            )
        end

        test "uses a native 303 redirect after Turbo creates an invitation" do
            context = insert_account_context("turbo-create-redirect")
            owner_role = insert_role(
                context,
                name: "turbo-create-owner",
                permission_level: 100
            )
            target_role = insert_role(
                context,
                name: "turbo-create-member",
                permission_level: 50
            )
            assign_role(context.fetch(:user), owner_role)

            with_authenticated_request(context.fetch(:user)) do
                post :create, params: {
                    invite: {
                        email: "turbo-create@example.com",
                        role_id: target_role.id
                    }
                }, format: :turbo_stream
            end

            invitation = LesliShield::Invite.find_by!(
                email: "turbo-create@example.com"
            )
            assert_response :see_other
            assert_redirected_to invite_path(invitation)
            refute_includes response.body, "Turbo.visit"
        end

        test "renders status filters contextual actions and an empty state" do
            context = insert_account_context("index-ux")
            invite = insert_invite(
                context,
                email: "index-ux@example.com"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index
            end

            assert_response :success
            assert_select "a[href='#{invites_path(status: "expired")}']"
            assert_select "span", text: I18n.t(
                "lesli_shield.invites.statuses.pending"
            )
            assert_select "form[action='#{cancel_invite_path(invite)}']"

            empty_context = insert_account_context("index-empty")

            with_authenticated_request(empty_context.fetch(:user)) do
                get :index
            end

            assert_response :success
            assert_select "h2", text: I18n.t(
                "lesli_shield.invites.empty_title"
            )
            assert_select "a[href='#{new_invite_path}']", text: I18n.t(
                "lesli_shield.invites.empty_action"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index, params: { status: "accepted" }
            end

            assert_response :success
            assert_select "h2", text: I18n.t(
                "lesli_shield.invites.empty_filtered_title"
            )
            assert_select "a[href='#{invites_path}']", text: I18n.t(
                "lesli_shield.invites.empty_filtered_action"
            )
        end

        test "ignores lifecycle attributes submitted by the browser" do
            @controller.params = ActionController::Parameters.new(
                invite: {
                    email: "person@example.com",
                    role_id: "12",
                    telephone: "+502 5555 5555",
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
            refute permitted_attributes.key?(:telephone)
        end

        test "offers only active roles assignable by the current user" do
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
                @controller.send(:set_assignable_roles)
                offered_roles = @controller.instance_variable_get(
                    :@assignable_roles
                )

                assert_includes offered_roles, current_role
                assert_includes offered_roles, assignable_role
                refute_includes offered_roles, elevated_role
                refute_includes offered_roles, inactive_role
                refute_includes offered_roles, foreign_role
            end
        end

        test "registers only the supported invitation actions" do
            actions = LesliShield::Engine.routes.routes.filter_map do |route|
                defaults = route.defaults
                next unless defaults[:controller] == "lesli_shield/invites"

                defaults[:action]
            end.uniq.sort

            assert_equal %w[cancel create index new resend show], actions
        end

        test "exposes resend and cancel in the role privilege matrix" do
            context = insert_account_context("privilege-matrix")
            role = insert_role(
                context,
                name: "privilege-manager",
                permission_level: 100
            )
            assign_role(context.fetch(:user), role)
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

            privilege_matrix = RolePermissionService
                .new(context.fetch(:user))
                .matrix(role)
            invite_resource = privilege_matrix
                .flat_map { |engine| engine.fetch(:resources) }
                .find do |resource|
                    resource.fetch(:route) == "lesli_shield/invites"
                end
            invite_actions = invite_resource.fetch(:actions).index_by do |action|
                action.fetch(:action)
            end

            assert invite_actions.fetch("resend").fetch(:assigned)
            assert invite_actions.fetch("cancel").fetch(:assigned)
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

        def insert_invite(
            context,
            email:,
            status: :pending,
            expires_at: 1.day.from_now
        )
            timestamp = Time.current
            invite_id = Invite.insert_all!([{
                account_id: context.fetch(:shield_account).id,
                invited_by_id: context.fetch(:user).id,
                email: email,
                status: Invite.statuses.fetch(status.to_s),
                expires_at: expires_at,
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
            with_controller_methods(current_user: user) { yield }
        end

        def with_authenticated_request(user)
            with_controller_methods(
                current_user: user,
                authenticate_request: true,
                authorize_request: true,
                log_requests: true
            ) do
                @routes = LesliShield::Engine.routes
                yield
            end
        end

        def with_controller_methods(overrides)
            controller_singleton = @controller.singleton_class
            original_methods = {}

            overrides.each do |method_name, return_value|
                if controller_singleton.instance_methods(false).include?(method_name)
                    original_methods[method_name] = controller_singleton
                        .instance_method(method_name)
                end

                controller_singleton.define_method(method_name) { return_value }
            end

            yield
        ensure
            overrides.each_key do |method_name|
                controller_singleton.remove_method(method_name)
                next unless original_methods.key?(method_name)

                controller_singleton.define_method(
                    method_name,
                    original_methods.fetch(method_name)
                )
            end
        end
    end
end
