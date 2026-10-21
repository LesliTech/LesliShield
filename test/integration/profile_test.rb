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

        private

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
