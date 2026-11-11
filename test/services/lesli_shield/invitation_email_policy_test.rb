require "test_helper"

module LesliShield
    class InvitationEmailPolicyTest < ActiveSupport::TestCase
        setup do
            @account = create_account("destination")
        end

        test "allows an email without an existing user" do
            decision = evaluate(" Available@Example.COM ")

            assert_equal :available, decision.status
            assert decision.allowed?
            refute decision.recoverable?
        end

        test "rejects an existing member of the destination account" do
            user = create_user("member@example.com", account: @account)

            decision = evaluate(user.email)

            assert_equal :member, decision.status
            assert_equal user, decision.user
            assert decision.rejected?
        end

        test "rejects a user belonging to another account" do
            other_account = create_account("other")
            user = create_user("other@example.com", account: other_account)

            decision = evaluate(user.email)

            assert_equal :other_account, decision.status
            assert decision.rejected?
        end

        test "allows an unconfirmed accountless user to be securely recovered" do
            user = create_user(
                "recoverable@example.com",
                account: nil,
                confirmed_at: nil
            )

            decision = evaluate(user.email)

            assert_equal :recoverable, decision.status
            assert decision.allowed?
            assert decision.recoverable?
        end

        test "rejects a deleted user" do
            user = create_user(
                "deleted@example.com",
                account: nil,
                confirmed_at: nil,
                deleted_at: Time.current
            )

            decision = evaluate(user.email)

            assert_equal :deleted, decision.status
            assert_equal user, decision.user
            assert decision.rejected?
        end

        test "rejects a confirmed accountless user for manual review" do
            user = create_user("orphan@example.com", account: nil)

            decision = evaluate(user.email)

            assert_equal :existing_without_account, decision.status
            assert decision.rejected?
        end

        test "invite creation enforces rejected email decisions" do
            shield_account = LesliShield::Account.create!(account: @account)
            user = create_user("existing-member@example.com", account: @account)
            invite = Invite.new(account: shield_account, email: user.email)

            invite.validate

            assert_includes(
                invite.errors[:email],
                I18n.t("lesli_shield.invites.email_member")
            )
        end

        test "invite creation permits secure recovery without changing the user" do
            shield_account = LesliShield::Account.create!(account: @account)
            user = create_user(
                "recover-during-acceptance@example.com",
                account: nil,
                confirmed_at: nil
            )
            original_attributes = user.attributes
            invite = Invite.new(account: shield_account, email: user.email)

            invite.validate

            assert_empty invite.errors[:email]
            assert_equal original_attributes, user.reload.attributes
        end

        test "requires a destination account" do
            error = assert_raises(ArgumentError) do
                InvitationEmailPolicy.new(
                    account: nil,
                    email: "person@example.com"
                )
            end

            assert_equal "account is required", error.message
        end

        private

        def evaluate(email)
            InvitationEmailPolicy.new(
                account: @account,
                email: email
            ).evaluate
        end

        def create_account(label)
            identifier = SecureRandom.hex(6)
            timestamp = Time.current
            email = "#{label}-#{identifier}@example.com"

            Lesli::Account.insert_all!([{
                name: "#{label.capitalize} account",
                email: email,
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::Account.find_by!(email: email)
        end

        def create_user(email, account:, confirmed_at: Time.current, deleted_at: nil)
            timestamp = Time.current

            # Bypass acts_as_paranoid's default creation scope so tests can
            # represent an already deleted identity faithfully.
            Lesli::User.unscoped.insert_all!([{
                uid: "LID-#{SecureRandom.hex(6)}",
                email: email,
                account_id: account&.id,
                active: true,
                confirmed_at: confirmed_at,
                deleted_at: deleted_at,
                created_at: timestamp,
                updated_at: timestamp
            }])

            Lesli::User.with_deleted.find_by!(email: email)
        end
    end
end
