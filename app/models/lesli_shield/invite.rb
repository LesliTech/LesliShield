module LesliShield
    class Invite < ApplicationRecord
        class InvalidStatusTransition < StandardError; end

        DEFAULT_EXPIRATION = 7.days
        STATUS_TRANSITIONS = {
            "pending" => %w[accepted cancelled expired],
            "expired" => %w[pending],
            "accepted" => [],
            "cancelled" => []
        }.freeze

        belongs_to :account, class_name: "LesliShield::Account"
        belongs_to :invited_by,
            class_name: "Lesli::User",
            foreign_key: :invited_by_id
        belongs_to :role,
            class_name: "Lesli::Role",
            foreign_key: :role_id,
            optional: true
        belongs_to :accepted_user,
            class_name: "Lesli::User",
            foreign_key: :accepted_user_id,
            optional: true

        enum :status, {
            pending: 0,
            accepted: 1,
            cancelled: 2,
            expired: 3
        }, default: :pending, validate: true, scopes: false

        scope :pending, -> {
            where(status: statuses.fetch("pending"))
        }
        scope :active, -> {
            pending.where(expires_at: Time.current..)
        }
        scope :expired, -> {
            expired_by_status = where(status: statuses.fetch("expired"))
            expired_by_time = pending.where(expires_at: (..Time.current))

            expired_by_status.or(expired_by_time)
        }
        scope :for_account, ->(account) {
            where(account: account)
        }

        before_validation :normalize_email
        before_validation :set_default_expiration, on: :create

        validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
        validate :email_can_be_invited, on: :create
        validate :role_belongs_to_inviting_account
        validate :status_transition_is_allowed, on: :update

        class << self
            def expiration_period
                configured_expiration = Lesli.config.shield&.dig(
                    :invitation_expiration
                )

                configured_expiration.presence || DEFAULT_EXPIRATION
            end

            def allowed_status_transition?(from:, to:)
                STATUS_TRANSITIONS.fetch(from.to_s, []).include?(to.to_s)
            end
        end

        # Accepting an invitation is intentionally a terminal operation. The
        # acceptance service will call this only after creating the user,
        # assigning its account and role, and confirming its email atomically.
        def accept!(accepted_user)
            transition_to!(
                :accepted,
                accepted_user: accepted_user,
                accepted_at: Time.current
            )
        end

        def cancel!
            transition_to!(
                :cancelled,
                cancelled_at: Time.current
            )
        end

        def expire!
            transition_to!(:expired)
        end

        # Resending is the only operation that can reactivate an expired
        # invitation. No user record is created or modified here.
        def resend!
            unless resendable?
                raise InvalidStatusTransition,
                    "cannot resend an invitation with status #{status}"
            end

            transition_to!(
                :pending,
                expires_at: Time.current + self.class.expiration_period
            )
        end

        def resendable?
            expired?
        end

        def resend_available?
            resendable? || (pending? && expires_at.present? && expires_at.past?)
        end

        def cancellable?
            pending?
        end

        def lifecycle_status
            return "expired" if pending? && expires_at.present? && expires_at.past?

            status
        end

        def acceptance_available?
            pending? && expires_at.present? && expires_at.future?
        end

        private

        def normalize_email
            self.email = email.to_s.strip.downcase.presence
        end

        def set_default_expiration
            self.expires_at ||= Time.current + self.class.expiration_period
        end

        def email_can_be_invited
            destination_account = account&.account
            return if destination_account.blank? || email.blank?

            decision = InvitationEmailPolicy.new(
                account: destination_account,
                email: email
            ).evaluate
            return if decision.allowed?

            errors.add(
                :email,
                I18n.t("lesli_shield.invites.email_#{decision.status}")
            )
        end

        def role_belongs_to_inviting_account
            return if role.blank? || account.blank?
            return if role.account == account.account

            errors.add(
                :role,
                I18n.t("lesli_shield.invites.role_account_mismatch")
            )
        end

        def transition_to!(target_status, attributes = {})
            unless self.class.allowed_status_transition?(
                from: status,
                to: target_status
            )
                raise InvalidStatusTransition,
                    "cannot transition invitation from #{status} to #{target_status}"
            end

            update!(attributes.merge(status: target_status))
        end

        def status_transition_is_allowed
            previous_status, next_status = status_change_to_be_saved
            return if previous_status.nil?
            return if self.class.allowed_status_transition?(
                from: previous_status,
                to: next_status
            )

            errors.add(
                :status,
                I18n.t("lesli_shield.invites.invalid_status_transition"),
                from: previous_status,
                to: next_status
            )
        end
    end
end
