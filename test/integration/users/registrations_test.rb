require "test_helper"

module Users
    class RegistrationsTest < ActionDispatch::IntegrationTest
        setup do
            reset!
            ActionMailer::Base.deliveries.clear
            @original_allow_registration = Lesli.config.security[:allow_registration]
            @original_demo_mode = Lesli.config.demo
            Lesli.config.security[:allow_registration] = true
            Lesli.config.demo = false
        end

        teardown do
            Lesli.config.security[:allow_registration] = @original_allow_registration
            Lesli.config.demo = @original_demo_mode
        end

        test "renders the native registration fields without exposing demo credentials" do
            Lesli.config.demo = true

            get new_user_registration_path

            assert_response :success
            assert_select 'input[name="user[email]"][required][autocomplete="email"]'
            assert_select 'input[name="user[password]"][required][autocomplete="new-password"]'
            assert_select 'input[name="user[password_confirmation]"][required][autocomplete="new-password"]'
            assert_select 'input[name="user[password]"]', value: "", count: 1
            assert_select 'input[name="user[password_confirmation]"]',
                value: "",
                count: 1
            refute_includes response.body, Lesli.config.security[:password]
        end

        test "creates an unconfirmed user and sends one confirmation email" do
            email = " New-User-#{SecureRandom.hex(6)}@Example.COM "

            assert_difference -> { Lesli::User.count }, 1 do
                assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
                    post user_registration_path, params: registration_params(email)
                end
            end

            user = Lesli::User.order(:id).last

            assert_response :see_other
            assert_redirected_to new_user_registration_path
            assert_equal email.strip.downcase, user.email
            assert user.active?
            refute user.confirmed?
            assert_nil user.account
            assert_empty user.roles
            assert_nil request.session["warden.user.user.key"]
            assert_equal(
                I18n.t("devise.registrations.signed_up_but_invalid"),
                flash[:notice]
            )
            assert_equal [user.email], ActionMailer::Base.deliveries.last.to
        end

        test "renders validation errors without echoing either password" do
            email = "invalid-registration-#{SecureRandom.hex(6)}@example.com"

            assert_no_difference -> { Lesli::User.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    post user_registration_path, params: {
                        user: {
                            email: email,
                            password: "password-123",
                            password_confirmation: "different-password"
                        }
                    }
                end
            end

            assert_response :unprocessable_content
            assert_select "#error_explanation"
            assert_select 'input[name="user[email]"]', value: email
            refute_includes response.body, 'value="password-123"'
            refute_includes response.body, 'value="different-password"'
        end

        test "does not create another user or send email for a duplicate address" do
            existing_user = build_user(
                "duplicate-registration-#{SecureRandom.hex(6)}@example.com"
            )
            existing_user.skip_confirmation_notification!
            existing_user.save!
            ActionMailer::Base.deliveries.clear

            assert_no_difference -> { Lesli::User.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    post user_registration_path,
                        params: registration_params(existing_user.email.upcase)
                end
            end

            assert_response :unprocessable_content
            assert_select "#error_explanation"
        end

        test "blocks both the registration page and account creation when disabled" do
            Lesli.config.security[:allow_registration] = false

            get new_user_registration_path

            assert_response :found
            assert_redirected_to new_user_session_path

            assert_no_difference -> { Lesli::User.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    post user_registration_path,
                        params: registration_params("blocked@example.com")
                end
            end

            assert_response :see_other
            assert_redirected_to new_user_session_path
            assert_equal(
                I18n.t(
                    "lesli_shield.devise/registrations.message_registration_not_allowed"
                ),
                flash[:alert]
            )
        end

        private

        def registration_params(email)
            {
                user: {
                    email: email,
                    password: "password-123",
                    password_confirmation: "password-123"
                }
            }
        end

        def build_user(email)
            Lesli::User.new(
                email: email,
                password: "password-123",
                password_confirmation: "password-123"
            )
        end
    end
end
