require "test_helper"

module Users
    class PasswordsTest < ActionDispatch::IntegrationTest
        setup do
            reset!
            ActionMailer::Base.deliveries.clear
        end

        test "renders an accessible password recovery form" do
            get new_user_password_path

            assert_response :success
            assert_select 'input[type="email"][name="user[email]"][required]'
            assert_select 'input[type="email"][autocomplete="email"]'
            assert_select 'button[type="submit"]'
        end

        test "requests password recovery without revealing whether the email exists" do
            user = create_recoverable_user

            assert_difference(
                -> { ActionMailer::Base.deliveries.count },
                1
            ) do
                post user_password_path, params: {
                    user: { email: user.email }
                }
            end

            assert_response :see_other
            assert_redirected_to new_user_password_path
            assert_equal(
                I18n.t("devise.passwords.send_paranoid_instructions"),
                flash[:notice]
            )

            assert_no_difference(
                -> { ActionMailer::Base.deliveries.count }
            ) do
                post user_password_path, params: {
                    user: { email: "missing@example.com" }
                }
            end

            assert_response :see_other
            assert_redirected_to new_user_password_path
            assert_equal(
                I18n.t("devise.passwords.send_paranoid_instructions"),
                flash[:notice]
            )
        end

        test "uses the password reset subject and named route" do
            user = create_recoverable_user

            post user_password_path, params: {
                user: { email: user.email }
            }

            mail = ActionMailer::Base.deliveries.last

            assert_equal(
                I18n.t("lesli_shield.devise/passwords.mailer_subject"),
                mail.subject
            )
            assert_includes mail.body.encoded, "/password/edit?reset_password_token="
        end

        test "resets the password and creates one application session and audit event" do
            user = create_recoverable_user
            token = password_reset_token_for(user)
            user.update!(password_expiration_at: 1.hour.ago)

            assert_difference(
                -> { LesliShield::User::Session.where(user_id: user.id).count },
                1
            ) do
                put user_password_path, params: password_update_params(token)
            end

            assert_response :see_other
            assert user.reload.valid_password?("new-password-123")
            assert_nil user.password_expiration_at
            assert request.session[:user_session_id]

            assert_equal(
                request.session[:user_session_id],
                LesliShield::User::Session.where(user_id: user.id).sole.id
            )
        end

        test "changes the password but does not sign in an ineligible user" do
            user = create_recoverable_user(active: false)
            token = password_reset_token_for(user)

            assert_no_difference(
                -> { LesliShield::User::Session.where(user_id: user.id).count }
            ) do
                put user_password_path, params: password_update_params(token)
            end

            assert_response :see_other
            assert_redirected_to new_user_session_path
            assert user.reload.valid_password?("new-password-123")
            assert_nil request.session[:user_session_id]
        end

        test "keeps password values out of the response after validation fails" do
            user = create_recoverable_user
            token = password_reset_token_for(user)
            encrypted_password = user.encrypted_password

            put user_password_path, params: {
                user: {
                    reset_password_token: token,
                    password: "new-password-123",
                    password_confirmation: "different-password"
                }
            }

            assert_response :unprocessable_content
            assert_equal encrypted_password, user.reload.encrypted_password
            refute_includes response.body, 'value="new-password-123"'
            refute_includes response.body, 'value="different-password"'
            assert_select(
                'input[name="user[reset_password_token]"]',
                value: token,
                count: 1
            )
            assert_nil request.session[:user_session_id]
        end

        test "protects reset tokens from referrer and browser caches" do
            user = create_recoverable_user
            token = password_reset_token_for(user)

            get edit_user_password_path(reset_password_token: token)

            assert_response :success
            assert_equal "same-origin", response.headers["Referrer-Policy"]
            assert_equal "no-store", response.headers["Cache-Control"]
        end

        private

        def create_recoverable_user(active: true)
            identifier = SecureRandom.hex(8)
            account = create_account(identifier)
            role = create_role(account, identifier)
            user = Lesli::User.create!(
                account: account,
                active: active,
                confirmed_at: Time.current,
                email: "password-#{identifier}@example.com",
                password: "password-123",
                password_confirmation: "password-123"
            )

            LesliShield::User::Role.create!(
                user_id: user.id,
                role_id: role.id
            )

            user
        end

        def create_account(identifier)
            email = "password-account-#{identifier}@example.com"
            timestamp = Time.current

            Lesli::Account.insert_all!([{
                name: "Password test",
                email: email,
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Account.find_by!(email: email)
        end

        def create_role(account, identifier)
            name = "password-role-#{identifier}"
            timestamp = Time.current

            Lesli::Role.insert_all!([{
                account_id: account.id,
                active: true,
                name: name,
                code: name,
                permission_level: 10,
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Role.find_by!(account: account, name: name)
        end

        def password_reset_token_for(user)
            user.send(:set_reset_password_token)
        end

        def password_update_params(token)
            {
                user: {
                    reset_password_token: token,
                    password: "new-password-123",
                    password_confirmation: "new-password-123"
                }
            }
        end
    end
end
