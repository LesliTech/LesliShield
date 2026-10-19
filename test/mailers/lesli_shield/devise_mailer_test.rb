# frozen_string_literal: true

require "test_helper"

module LesliShield
    class DeviseMailerTest < ActionMailer::TestCase
        setup do
            @user = Lesli::User.new(
                email: "ada@example.com",
                first_name: "Ada",
                last_name: "Lovelace"
            )
            @user.account = Lesli::Account.new(name: "Analytical Engines")
        end

        test "builds password reset email metadata and rendered content" do
            mail = DeviseMailer.reset_password_instructions(
                @user,
                "reset-token"
            )
            body = mail.body.decoded

            assert_equal [Devise.mailer_sender], mail.from
            assert_equal [@user.email], mail.to
            assert_equal(
                I18n.t("lesli_shield.devise/passwords.mailer_subject"),
                mail.subject
            )
            assert_includes body, "Hello Ada Lovelace"
            assert_includes(
                body,
                "http://example.com/password/edit?reset_password_token=reset-token"
            )
            assert_fully_rendered body
        end

        test "sends confirmation to the pending address with its token URL" do
            @user.unconfirmed_email = "new-ada@example.com"
            mail = DeviseMailer.confirmation_instructions(
                @user,
                "confirmation-token"
            )
            body = mail.body.decoded

            assert_equal [Devise.mailer_sender], mail.from
            assert_equal [@user.unconfirmed_email], mail.to
            assert_equal(
                I18n.t(
                    "lesli_shield.devise/confirmations.mailer_confirmation_subject"
                ),
                mail.subject
            )
            assert_includes(
                body,
                "http://example.com/confirmation?confirmation_token=confirmation-token"
            )
            assert_includes body, "Confirm my account"
            assert_fully_rendered body
        end

        test "builds welcome email with the user and application URL" do
            mail = DeviseMailer.welcome(@user)
            body = mail.body.decoded

            assert_equal [Devise.mailer_sender], mail.from
            assert_equal [@user.email], mail.to
            assert_equal(
                I18n.t(
                    "lesli_shield.devise/confirmations.mailer_welcome_subject"
                ),
                mail.subject
            )
            assert_includes body, "Hi Ada Lovelace."
            assert_includes body, %(href="http://example.com/")
            assert_fully_rendered body
        end

        test "honors headers supplied by Devise" do
            mail = DeviseMailer.reset_password_instructions(
                @user,
                "reset-token",
                from: "security@example.com",
                reply_to: "support@example.com",
                subject: "Custom password instructions",
                to: "alternate@example.com"
            )

            assert_equal ["security@example.com"], mail.from
            assert_equal ["support@example.com"], mail.reply_to
            assert_equal ["alternate@example.com"], mail.to
            assert_equal "Custom password instructions", mail.subject
        end

        test "uses the host mailer sender when Devise does not override it" do
            original_sender = Devise.mailer_sender
            original_defaults = Rails.application.config.action_mailer.default_options

            Devise.mailer_sender = nil
            Rails.application.config.action_mailer.default_options = {
                from: "host-application@example.com"
            }

            mail = DeviseMailer.welcome(@user)

            assert_equal ["host-application@example.com"], mail.from
        ensure
            Devise.mailer_sender = original_sender
            Rails.application.config.action_mailer.default_options = original_defaults
        end

        test "uses the configured protocol host and port in every link" do
            original_options = Rails.application.config.action_mailer.default_url_options
            Rails.application.config.action_mailer.default_url_options = {
                host: "accounts.example.com",
                protocol: "https",
                port: 8443
            }

            reset_mail = DeviseMailer.reset_password_instructions(
                @user,
                "reset-token"
            )
            welcome_mail = DeviseMailer.welcome(@user)

            assert_includes(
                reset_mail.body.decoded,
                "https://accounts.example.com:8443/password/edit?reset_password_token=reset-token"
            )
            assert_includes(
                welcome_mail.body.decoded,
                %(href="https://accounts.example.com:8443/")
            )
        ensure
            Rails.application.config.action_mailer.default_url_options = original_options
        end

        private

        def assert_fully_rendered(body)
            refute_includes body, "<%"
        end
    end
end
