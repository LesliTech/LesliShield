require "test_helper"

module LesliShield
    class ProfileTest < ActionDispatch::IntegrationTest
        include Devise::Test::IntegrationHelpers

        setup do
            @audit_analytics_enabled = Lesli.config.audit[:enable_analytics]
            Lesli.config.audit[:enable_analytics] = false

            reset!
            @user = create_profile_user
            sign_in @user
        end

        teardown do
            Lesli.config.audit[:enable_analytics] = @audit_analytics_enabled
        end

        test "shows the authenticated user profile without administrative privileges" do
            get lesli_shield.profile_path

            assert_response :success
            assert_select "h5", text: @user.full_name
            assert_select "a[href='mailto:#{@user.email}']"
            assert_select "form[action='#{lesli_shield.profile_path}']"
            assert_select "#security-tab span", text: "Security"
            assert_select "form[action='#{lesli_shield.profile_password_path}']"
            assert_select "input[name='user[current_password]'][type='password']"
            assert_select "input[name='user[password]'][type='password']"
            assert_select "input[name='user[password_confirmation]'][type='password']"
            assert_select "a", text: "Privileges", count: 0
        end

        test "requires authentication" do
            sign_out @user

            get lesli_shield.profile_path

            assert_redirected_to "/login?r=#{lesli_shield.profile_path}"
        end

        test "returns only public profile fields as json" do
            get lesli_shield.profile_path, as: :json

            assert_response :success

            payload = response.parsed_body
            assert_equal @user.id, payload["id"]
            assert_equal @user.email, payload["email"]
            assert_equal LesliShield::ProfilesController::PROFILE_FIELDS.map(&:to_s).sort,
                payload.keys.sort
            refute_includes payload, "encrypted_password"
            refute_includes payload, "reset_password_token"
        end

        test "updates only the authenticated user's profile fields" do
            patch lesli_shield.profile_path, params: {
                user: {
                    first_name: "Updated",
                    last_name: "Profile",
                    active: false
                }
            }

            assert_response :see_other
            assert_redirected_to lesli_shield.profile_path

            @user.reload

            assert_equal "Updated", @user.first_name
            assert_equal "Profile", @user.last_name
            assert_equal "UP", @user.alias
            assert_predicate @user, :active?
        end

        test "renders validation errors without persisting invalid changes" do
            original_email = @user.email

            patch lesli_shield.profile_path, params: {
                user: { email: "not-an-email" }
            }

            assert_response :unprocessable_content
            assert_select "form[action='#{lesli_shield.profile_path}']"
            assert_equal original_email, @user.reload.email
        end

        test "changes the password and keeps the current web session" do
            @user.update_column(:password_expiration_at, 1.day.ago)

            patch lesli_shield.profile_password_path, params: {
                user: {
                    current_password: "password-123",
                    password: "new-password-456",
                    password_confirmation: "new-password-456"
                }
            }

            assert_response :see_other
            assert_redirected_to lesli_shield.profile_path(tab: "security")

            @user.reload
            assert @user.valid_password?("new-password-456")
            refute @user.valid_password?("password-123")
            assert_nil @user.password_expiration_at

            get lesli_shield.profile_path
            assert_response :success
        end

        test "rejects a password change when the current password is invalid" do
            patch lesli_shield.profile_password_path, params: {
                user: {
                    current_password: "incorrect-password",
                    password: "new-password-456",
                    password_confirmation: "new-password-456"
                }
            }

            assert_response :unprocessable_content
            assert_select "form[action='#{lesli_shield.profile_password_path}']"
            assert @user.reload.valid_password?("password-123")
            refute @user.valid_password?("new-password-456")
        end

        test "rejects a password change when confirmation does not match" do
            patch lesli_shield.profile_password_path, params: {
                user: {
                    current_password: "password-123",
                    password: "new-password-456",
                    password_confirmation: "different-password"
                }
            }

            assert_response :unprocessable_content
            assert @user.reload.valid_password?("password-123")
            refute @user.valid_password?("new-password-456")
        end

        test "returns turbo validation feedback without echoing passwords" do
            patch lesli_shield.profile_password_path,
                params: {
                    user: {
                        current_password: "incorrect-password",
                        password: "new-password-456",
                        password_confirmation: "new-password-456"
                    }
                },
                headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

            assert_response :unprocessable_content
            assert_select "turbo-stream[target='application-lesli-notifications']"
            assert_select "turbo-stream[action='replace'][target='shield-profile-password-form']"
            refute_includes response.body, "incorrect-password"
            refute_includes response.body, "new-password-456"
        end

        test "revokes other application sessions after changing the password" do
            current_session = create_application_session
            other_session = create_application_session

            password = LesliShield::Profile::PasswordService
                .new(@user)
                .update(
                    {
                        current_password: "password-123",
                        password: "new-password-456",
                        password_confirmation: "new-password-456"
                    },
                    current_session_id: current_session.id
                )

            assert_predicate password, :successful?
            assert LesliShield::User::Session.exists?(current_session.id)
            refute LesliShield::User::Session.exists?(other_session.id)
            assert LesliShield::User::Session.with_deleted.exists?(other_session.id)
        end

        private

        def create_application_session
            @user.sessions.create!(
                remote: "127.0.0.1",
                session_source: "devise_standard_session",
                last_used_at: Time.current,
                usage_count: 1
            )
        end

        def create_profile_user
            identifier = SecureRandom.hex(8)
            timestamp = Time.current

            Lesli::Account.insert_all!([{
                name: "Profile test",
                email: "profile-account-#{identifier}@example.com",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])
            account = Lesli::Account.find_by!(
                email: "profile-account-#{identifier}@example.com"
            )

            Lesli::Role.insert_all!([{
                account_id: account.id,
                active: true,
                name: "profile-role-#{identifier}",
                code: "profile-role-#{identifier}",
                permission_level: 10,
                created_at: timestamp,
                updated_at: timestamp
            }])
            role = Lesli::Role.find_by!(
                account: account,
                name: "profile-role-#{identifier}"
            )

            user = Lesli::User.create!(
                account: account,
                confirmed_at: Time.current,
                email: "profile-#{identifier}@example.com",
                first_name: "Profile",
                last_name: "User",
                password: "password-123",
                password_confirmation: "password-123"
            )

            LesliShield::User::Role.create!(user: user, role: role)
            user
        end
    end
end
