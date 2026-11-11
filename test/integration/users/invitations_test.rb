# frozen_string_literal: true

require "test_helper"

module Users
    class InvitationsTest < ActionDispatch::IntegrationTest
        setup do
            @context = insert_account_context
            @invitation = insert_invitation
            @token = @invitation.signed_id(
                purpose: LesliShield::InvitationService::ACCEPTANCE_PURPOSE,
                expires_in: 1.day
            )
        end

        test "renders the invited email as readonly and profile fields as editable" do
            assert_no_difference -> { Lesli::User.count } do
                get user_invitation_path(invitation_token: @token)
            end

            assert_response :success
            assert_equal "no-store", response.headers["Cache-Control"]
            assert_equal "same-origin", response.headers["Referrer-Policy"]
            assert_includes response.body, @context.fetch(:account).name
            assert_includes response.body, @context.fetch(:role).name
            assert_select 'input[name="user[email]"][readonly]',
                value: @invitation.email
            assert_select 'input[name="user[first_name]"][required]'
            assert_select 'input[name="user[last_name]"][required]'
            assert_select 'input[name="user[telephone]"]'
            assert_select 'input[name="user[password]"][required]'
            assert_select 'input[name="user[password_confirmation]"][required]'
            assert_select 'input[name="invitation_token"]', value: @token
        end

        test "accepts the invitation and redirects to login" do
            assert_difference -> { Lesli::User.count }, 1 do
                patch user_invitation_path, params: {
                    invitation_token: @token,
                    user: valid_user_attributes
                }
            end

            accepted_user = Lesli::User.find_by!(email: @invitation.email)
            @invitation.reload

            assert_response :see_other
            assert_redirected_to new_user_session_path
            assert accepted_user.confirmed?
            assert_equal @context.fetch(:account), accepted_user.account
            assert_equal [@context.fetch(:role)], accepted_user.roles.to_a
            assert_equal accepted_user, @invitation.accepted_user
            assert @invitation.accepted?
        end

        test "keeps the invitation pending when user validation fails" do
            assert_no_difference -> { Lesli::User.count } do
                patch user_invitation_path, params: {
                    invitation_token: @token,
                    user: valid_user_attributes.merge(
                        password_confirmation: "different-password"
                    )
                }
            end

            assert_response :unprocessable_content
            assert_equal "no-store", response.headers["Cache-Control"]
            assert_equal "same-origin", response.headers["Referrer-Policy"]
            assert_select "#error_explanation"
            assert @invitation.reload.pending?
            assert_nil @invitation.accepted_user
        end

        test "renders a clear error for an invalid invitation" do
            get user_invitation_path(invitation_token: "invalid-token")

            assert_response :not_found
            assert_equal "no-store", response.headers["Cache-Control"]
            assert_select "h1", text: I18n.t(
                "lesli_shield.invites.acceptance_invalid_title"
            )
        end

        test "renders a clear error for an already used invitation" do
            LesliShield::InvitationService.new(nil).accept!(
                token: @token,
                user_attributes: valid_user_attributes
            )

            get user_invitation_path(invitation_token: @token)

            assert_response :gone
            assert_select "h1", text: I18n.t(
                "lesli_shield.invites.acceptance_used_title"
            )
        end

        test "renders a clear error for a cancelled invitation" do
            @invitation.cancel!

            get user_invitation_path(invitation_token: @token)

            assert_response :gone
            assert_select "h1", text: I18n.t(
                "lesli_shield.invites.acceptance_cancelled_title"
            )
        end

        test "renders a clear error for an expired invitation" do
            @invitation.expire!

            get user_invitation_path(invitation_token: @token)

            assert_response :gone
            assert_select "h1", text: I18n.t(
                "lesli_shield.invites.acceptance_expired_title"
            )
        end

        private

        def insert_account_context
            identifier = SecureRandom.hex(6)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "invitation-account-#{identifier}@example.com",
                name: "Invitation account #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            shield_account_id = LesliShield::Account.insert_all!([{
                account_id: account_id,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            owner_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "INVITER-#{identifier}",
                email: "inviter-#{identifier}@example.com",
                encrypted_password: "",
                active: true,
                confirmed_at: timestamp,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            role_id = Lesli::Role.insert_all!([{
                account_id: account_id,
                name: "member-#{identifier}",
                code: "member-#{identifier}",
                permission_level: 50,
                active: true,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            {
                account: Lesli::Account.find(account_id),
                shield_account: LesliShield::Account.find(shield_account_id),
                owner: Lesli::User.find(owner_id),
                role: Lesli::Role.find(role_id)
            }
        end

        def insert_invitation
            timestamp = Time.current
            invitation_id = LesliShield::Invite.insert_all!([{
                account_id: @context.fetch(:shield_account).id,
                invited_by_id: @context.fetch(:owner).id,
                role_id: @context.fetch(:role).id,
                email: "invited-#{SecureRandom.hex(6)}@example.com",
                status: LesliShield::Invite.statuses.fetch("pending"),
                expires_at: 1.day.from_now,
                sent_at: timestamp,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            LesliShield::Invite.find(invitation_id)
        end

        def valid_user_attributes
            {
                first_name: "Invited",
                last_name: "Person",
                telephone: "+502 5555 5555",
                password: "password-123",
                password_confirmation: "password-123"
            }
        end
    end
end
