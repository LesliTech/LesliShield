# frozen_string_literal: true

module LesliShield
    # Classifies an invitation recipient without creating or modifying a user.
    # The result is evaluated again while accepting the invitation to protect
    # against a user being created between invitation delivery and acceptance.
    class InvitationEmailPolicy
        AVAILABLE = :available
        MEMBER = :member
        OTHER_ACCOUNT = :other_account
        RECOVERABLE = :recoverable
        DELETED = :deleted
        EXISTING_WITHOUT_ACCOUNT = :existing_without_account

        ALLOWED_STATUSES = [AVAILABLE, RECOVERABLE].freeze

        Decision = Struct.new(:status, :user, keyword_init: true) do
            def allowed?
                ALLOWED_STATUSES.include?(status)
            end

            def rejected?
                !allowed?
            end

            def recoverable?
                status == RECOVERABLE
            end
        end

        attr_reader :account, :email

        def initialize(account:, email:)
            raise ArgumentError, "account is required" unless account

            @account = account
            @email = email.to_s.strip.downcase
        end

        def evaluate
            user = find_user

            return decision(AVAILABLE) unless user
            return decision(DELETED, user) if user.deleted_at.present?
            return decision(MEMBER, user) if user.account_id == account.id
            return decision(OTHER_ACCOUNT, user) if user.account_id.present?
            return decision(RECOVERABLE, user) unless user.confirmed?

            decision(EXISTING_WITHOUT_ACCOUNT, user)
        end

        private

        def find_user
            Lesli::User
                .with_deleted
                .find_by("LOWER(email) = ?", email)
        end

        def decision(status, user = nil)
            Decision.new(status: status, user: user)
        end
    end
end
