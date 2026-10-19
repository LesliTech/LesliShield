# frozen_string_literal: true

require "devise/orm/active_record"

# LesliShield is one possible authentication provider for Lesli. Because this
# provider selects Devise, all settings required by that implementation live
# here rather than in the framework core.
Devise.setup do |config|
    # Controllers, routes, and mail delivery
    config.parent_controller = "Lesli::ApplicationDeviseController"
    config.mailer_sender = "please-change-me-at-config-initializers-devise@example.com"
    config.mailer = "LesliShield::DeviseMailer"
    # Authentication routes are intentionally mounted in the host application
    # so every Lesli engine shares the same login. Devise must therefore build
    # its URLs through main_app, not through LesliShield's isolated router.
    config.router_name = :main_app

    # Authentication keys
    config.case_insensitive_keys = [:email]
    config.strip_whitespace_keys = [:email]

    # Authentication, recovery, and lock responses must not reveal whether the
    # submitted email belongs to an account.
    config.paranoid = true

    # Session behavior
    config.skip_session_storage = [:http_auth]
    config.expire_all_remember_me_on_sign_out = true
    config.http_authenticatable_on_xhr = false
    config.navigational_formats = [:html, :json]

    # The current navigation renders logout as a regular link. Retain GET until
    # those callers are migrated to submit a DELETE request.
    config.sign_out_via = :get

    # Password authentication
    config.stretches = Rails.env.test? ? 1 : 12
    config.password_length = 6..128
    config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

    # Confirmation and password recovery
    config.reconfirmable = true
    config.reset_password_within = 6.hours

    # Temporary account locking after repeated failed credentials.
    config.lock_strategy = :failed_attempts
    config.unlock_keys = [:email]
    config.unlock_strategy = :time
    config.maximum_attempts = 5
    config.unlock_in = 15.minutes
    config.last_attempt_warning = false

    # Rails/Hotwire response semantics
    config.responder.error_status = :unprocessable_content
    config.responder.redirect_status = :see_other
end
