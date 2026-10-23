require "test_helper"

module Users
    class ConfirmationsTest < ActionDispatch::IntegrationTest
        include ActiveJob::TestHelper

        setup do
            reset!
            ActionMailer::Base.deliveries.clear
            clear_enqueued_jobs
            clear_performed_jobs

            @original_allow_multiaccount = Lesli.config.security[:allow_multiaccount]
            Lesli.config.security[:allow_multiaccount] = true
        end

        teardown do
            Lesli.config.security[:allow_multiaccount] = @original_allow_multiaccount
        end

        test "renders an accessible resend-confirmation form" do
            get new_user_confirmation_path

            assert_response :success
            assert_select 'link[href*="confirmations"]'
            assert_select 'form[action="/confirmation"][method="post"]'
            assert_select 'input[name="user[email]"][required][autocomplete="email"]'
            assert_select 'button[type="submit"]'
        end

        test "confirms the user and atomically provisions an owned account" do
            user, raw_token = create_unconfirmed_user

            assert_difference -> { Lesli::Account.count }, 1 do
                assert_difference -> { LesliShield::User::Role.count }, 1 do
                    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
                        perform_enqueued_jobs do
                            get user_confirmation_path(
                                confirmation_token: raw_token
                            )
                        end
                    end
                end
            end

            user.reload

            assert_response :redirect
            assert_redirected_to new_user_session_path
            assert user.confirmed?
            assert_nil user.confirmation_token
            assert_equal user, user.account.user
            assert user.account.active?
            assert_equal ["owner"], user.roles.pluck(:name)
            assert_nil request.session["warden.user.user.key"]
            assert_equal I18n.t("devise.confirmations.confirmed"), flash[:notice]
            assert_equal "same-origin", response.headers["Referrer-Policy"]
            assert_equal "no-store", response.headers["Cache-Control"]

            welcome_email = ActionMailer::Base.deliveries.last
            assert_equal [user.email], welcome_email.to
            assert_equal(
                I18n.t(
                    "lesli_shield.devise/confirmations.mailer_welcome_subject"
                ),
                welcome_email.subject
            )
        end

        test "assigns the shared account and default role in single-account mode" do
            Lesli.config.security[:allow_multiaccount] = false
            account = Lesli::Account.first!
            default_role = create_role(account, "guest")
            user, raw_token = create_unconfirmed_user

            assert_no_difference -> { Lesli::Account.count } do
                assert_difference -> { LesliShield::User::Role.count }, 1 do
                    get user_confirmation_path(confirmation_token: raw_token)
                end
            end

            user.reload

            assert_response :redirect
            assert user.confirmed?
            assert_equal account, user.account
            assert_equal [default_role], user.roles.to_a
        end

        test "rejects an invalid token and offers to resend instructions" do
            assert_no_difference -> { Lesli::Account.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    get user_confirmation_path(
                        confirmation_token: "invalid-confirmation-token"
                    )
                end
            end

            assert_response :unprocessable_content
            assert_select "#error_explanation"
            assert_select 'input[name="user[email]"]'
            assert_equal "same-origin", response.headers["Referrer-Policy"]
            assert_equal "no-store", response.headers["Cache-Control"]
        end

        test "rejects an expired token without partially confirming the user" do
            user, raw_token = create_unconfirmed_user(sent_at: 4.hours.ago)
            encrypted_token = user.confirmation_token

            assert_no_difference -> { Lesli::Account.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    get user_confirmation_path(confirmation_token: raw_token)
                end
            end

            user.reload

            assert_response :unprocessable_content
            refute user.confirmed?
            assert_nil user.account
            assert_equal encrypted_token, user.confirmation_token
        end

        test "rolls confirmation back when account provisioning fails" do
            Lesli.config.security[:allow_multiaccount] = false
            user, raw_token = create_unconfirmed_user
            encrypted_token = user.confirmation_token

            assert_no_difference -> { Lesli::Account.count } do
                assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                    get user_confirmation_path(confirmation_token: raw_token)
                end
            end

            user.reload

            assert_response :unprocessable_content
            refute user.confirmed?
            assert_nil user.account
            assert_equal encrypted_token, user.confirmation_token
            assert_select "#error_explanation"
            assert_includes(
                response.body,
                I18n.t(
                    "lesli_shield.devise/confirmations.message_confirmation_failed"
                )
            )
        end

        test "resends instructions without revealing whether the email exists" do
            user, = create_unconfirmed_user

            assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
                post user_confirmation_path, params: {
                    user: { email: user.email }
                }
            end

            assert_response :see_other
            assert_redirected_to new_user_confirmation_path
            assert_equal(
                I18n.t("devise.confirmations.send_paranoid_instructions"),
                flash[:notice]
            )

            assert_no_difference -> { ActionMailer::Base.deliveries.count } do
                post user_confirmation_path, params: {
                    user: { email: "missing-confirmation@example.com" }
                }
            end

            assert_response :see_other
            assert_redirected_to new_user_confirmation_path
            assert_equal(
                I18n.t("devise.confirmations.send_paranoid_instructions"),
                flash[:notice]
            )
        end

        test "builds confirmation emails with the configured subject and named route" do
            user, = create_unconfirmed_user

            post user_confirmation_path, params: {
                user: { email: user.email }
            }

            confirmation_email = ActionMailer::Base.deliveries.last

            assert_equal(
                I18n.t(
                    "lesli_shield.devise/confirmations.mailer_confirmation_subject"
                ),
                confirmation_email.subject
            )
            assert_includes confirmation_email.body.encoded, "/confirmation?"
            assert_includes confirmation_email.body.encoded, "confirmation_token="
        end

        private

        def create_unconfirmed_user(sent_at: Time.current)
            identifier = SecureRandom.hex(8)
            raw_token = Devise.friendly_token
            encrypted_token = Devise.token_generator.digest(
                Lesli::User,
                :confirmation_token,
                raw_token
            )

            user = Lesli::User.new(
                email: "confirmation-#{identifier}@example.com",
                password: "password-123",
                password_confirmation: "password-123",
                confirmation_token: encrypted_token,
                confirmation_sent_at: sent_at
            )
            user.skip_confirmation_notification!
            user.save!

            [user, raw_token]
        end

        def create_account
            identifier = SecureRandom.hex(8)
            timestamp = Time.current
            email = "confirmation-account-#{identifier}@example.com"

            Lesli::Account.insert_all!([{
                name: "Confirmation test",
                email: email,
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Account.find_by!(email: email)
        end

        def create_role(account, name)
            timestamp = Time.current

            Lesli::Role.insert_all!([{
                account_id: account.id,
                active: true,
                name: name,
                code: "#{name}-#{SecureRandom.hex(4)}",
                permission_level: 10,
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Role.find_by!(account: account, name: name)
        end
    end
end
