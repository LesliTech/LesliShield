require "test_helper"

module Users
    class SessionsTest < ActionDispatch::IntegrationTest
        setup do
            reset!
            @original_path_after_login = Lesli.config.shield[:path_after_login]
            Lesli.config.shield[:path_after_login] = "/dashboard"
        end

        teardown do
            Lesli.config.shield[:path_after_login] = @original_path_after_login
        end

        test "signs in an eligible user and creates the application session" do
            user = create_login_user

            assert_difference(
                -> { LesliShield::User::Session.where(user_id: user.id).count },
                1
            ) do
                post "/login", params: login_params_for(user)
            end

            assert_response :see_other
            assert_redirected_to "/dashboard"
            assert request.session[:user_session_id]
        end

        test "rejects an ineligible user before creating the application session" do
            user = create_login_user(active: false)

            assert_no_difference(
                -> { LesliShield::User::Session.where(user_id: user.id).count }
            ) do
                post "/login", params: login_params_for(user)
            end

            assert_response :found
            assert_redirected_to new_user_session_path
            assert_nil request.session[:user_session_id]
        end

        test "preserves the requested destination after invalid credentials" do
            user = create_login_user

            assert_difference(
                -> { user.reload.failed_attempts },
                1
            ) do
                assert_no_difference(
                    -> { LesliShield::User::Session.where(user_id: user.id).count }
                ) do
                    post "/login", params: login_params_for(
                        user,
                        password: "incorrect-password",
                        redirect: "/reports"
                    )
                end
            end

            assert_response :unprocessable_content
            assert_select(
                'input[name="user[redirect]"][value="/reports"]',
                count: 1
            )
            assert_nil request.session[:user_session_id]
        end

        private

        def create_login_user(active: true)
            identifier = SecureRandom.hex(8)
            account = create_account(identifier)
            role = create_role(account, identifier)
            user = Lesli::User.create!(
                account: account,
                active: active,
                confirmed_at: Time.current,
                email: "login-#{identifier}@example.com",
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
            email = "account-#{identifier}@example.com"
            timestamp = Time.current

            Lesli::Account.insert_all!([{
                name: "Login test",
                email: email,
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Account.find_by!(email: email)
        end

        def create_role(account, identifier)
            name = "login-role-#{identifier}"
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

        def login_params_for(user, password: "password-123", redirect: nil)
            {
                user: {
                    email: user.email,
                    password: password,
                    redirect: redirect
                }
            }
        end
    end
end
