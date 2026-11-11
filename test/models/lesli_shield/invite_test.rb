require "test_helper"

module LesliShield
    class InviteTest < ActiveSupport::TestCase
        setup do
            @original_expiration = Lesli.config.shield[:invitation_expiration]
        end

        teardown do
            Lesli.config.shield[:invitation_expiration] = @original_expiration
        end

        test "defines the invitation lifecycle" do
            assert Invite.allowed_status_transition?(from: :pending, to: :accepted)
            assert Invite.allowed_status_transition?(from: :pending, to: :cancelled)
            assert Invite.allowed_status_transition?(from: :pending, to: :expired)
            assert Invite.allowed_status_transition?(from: :expired, to: :pending)

            refute Invite.allowed_status_transition?(from: :accepted, to: :pending)
            refute Invite.allowed_status_transition?(from: :cancelled, to: :pending)
            refute Invite.allowed_status_transition?(from: :expired, to: :accepted)
        end

        test "defines the invitation ownership associations" do
            invited_by = Invite.reflect_on_association(:invited_by)
            role = Invite.reflect_on_association(:role)
            accepted_user = Invite.reflect_on_association(:accepted_user)

            assert_equal "Lesli::User", invited_by.class_name
            assert_equal :invited_by_id, invited_by.foreign_key.to_sym
            assert_equal "Lesli::Role", role.class_name
            assert_equal :role_id, role.foreign_key.to_sym
            assert role.options[:optional]
            assert_equal "Lesli::User", accepted_user.class_name
            assert_equal :accepted_user_id, accepted_user.foreign_key.to_sym
            assert accepted_user.options[:optional]
        end

        test "normalizes email and validates its format" do
            invite = Invite.new(email: "  NOT-AN-EMAIL  ")

            refute invite.valid?
            assert_equal "not-an-email", invite.email
            assert invite.errors.of_kind?(:email, :invalid)
        end

        test "requires the selected role to belong to the inviting account" do
            inviting_account = Lesli::Account.new
            inviting_account.id = 101
            another_account = Lesli::Account.new
            another_account.id = 202

            shield_account = LesliShield::Account.new(
                account: inviting_account
            )
            invite = Invite.new(
                account: shield_account,
                email: "person@example.com",
                role: Lesli::Role.new(account: another_account)
            )

            refute invite.valid?
            assert_includes invite.errors[:role], I18n.t(
                "lesli_shield.invites.role_account_mismatch"
            )

            invite.role = Lesli::Role.new(account: inviting_account)
            invite.validate

            refute_includes invite.errors[:role], I18n.t(
                "lesli_shield.invites.role_account_mismatch"
            )
        end

        test "prevents duplicate pending invitations after normalizing email" do
            context = insert_account_context("duplicate-pending")
            first_invitation = Invite.create!(
                account: context.fetch(:shield_account),
                invited_by: context.fetch(:user),
                email: " Duplicate@Example.COM "
            )

            assert_equal "duplicate@example.com", first_invitation.email
            assert_raises(ActiveRecord::RecordNotUnique) do
                Invite.create!(
                    account: context.fetch(:shield_account),
                    invited_by: context.fetch(:user),
                    email: "duplicate@example.com"
                )
            end

            first_invitation.cancel!

            replacement = Invite.create!(
                account: context.fetch(:shield_account),
                invited_by: context.fetch(:user),
                email: "duplicate@example.com"
            )
            assert replacement.pending?
        end

        test "does not overwrite an explicitly assigned status during validation" do
            invite = Invite.new(
                email: "person@example.com",
                status: :cancelled
            )

            invite.validate

            assert invite.cancelled?
        end

        test "normalizes email and defaults to a pending seven-day invitation" do
            travel_to Time.zone.local(2026, 11, 11, 10, 0, 0) do
                invite = Invite.new(email: " Person@Example.COM ")
                invite.validate

                assert_equal "person@example.com", invite.email
                assert invite.pending?
                assert_equal 7.days.from_now, invite.expires_at
                assert invite.acceptance_available?
            end
        end

        test "uses the configured expiration period" do
            Lesli.config.shield[:invitation_expiration] = 48.hours

            travel_to Time.zone.local(2026, 11, 11, 10, 0, 0) do
                invite = Invite.new(email: "person@example.com")
                invite.validate

                assert_equal 48.hours.from_now, invite.expires_at
            end
        end

        test "acceptance is unavailable after expiration" do
            invite = Invite.new(
                email: "person@example.com",
                status: :pending,
                expires_at: 1.second.ago
            )

            refute invite.acceptance_available?
            assert invite.resend_available?
            assert invite.cancellable?
            assert_equal "expired", invite.lifecycle_status
        end

        test "accepted and cancelled invitations are terminal" do
            accepted = Invite.new(email: "accepted@example.com", status: :accepted)
            cancelled = Invite.new(email: "cancelled@example.com", status: :cancelled)

            assert_raises(Invite::InvalidStatusTransition) { accepted.resend! }
            assert_raises(Invite::InvalidStatusTransition) { cancelled.resend! }
            refute accepted.cancellable?
            refute cancelled.cancellable?
            assert_equal "accepted", accepted.lifecycle_status
            assert_equal "cancelled", cancelled.lifecycle_status
        end

        test "filters pending active expired and account invitations" do
            travel_to Time.zone.local(2026, 11, 11, 10, 0, 0) do
                first_context = insert_account_context("first")
                second_context = insert_account_context("second")

                active = insert_invite(
                    first_context,
                    email: "active@example.com",
                    status: :pending,
                    expires_at: 1.day.from_now
                )
                overdue = insert_invite(
                    first_context,
                    email: "overdue@example.com",
                    status: :pending,
                    expires_at: 1.minute.ago
                )
                explicitly_expired = insert_invite(
                    first_context,
                    email: "expired@example.com",
                    status: :expired,
                    expires_at: 1.day.from_now
                )
                other_account = insert_invite(
                    second_context,
                    email: "other@example.com",
                    status: :pending,
                    expires_at: 1.day.from_now
                )

                assert_equal_ids [active, overdue, other_account], Invite.pending
                assert_equal_ids [active, other_account], Invite.active
                assert_equal_ids [overdue, explicitly_expired], Invite.expired
                assert_equal_ids(
                    [active, overdue, explicitly_expired],
                    Invite.for_account(first_context.fetch(:shield_account))
                )
            end
        end

        test "records state transition timestamps and accepted user" do
            travel_to Time.zone.local(2026, 11, 11, 10, 0, 0) do
                context = insert_account_context("transitions")

                accepted = insert_invite(
                    context,
                    email: "accepted-transition@example.com"
                )
                accepted.accept!(context.fetch(:user))

                assert accepted.accepted?
                assert_equal context.fetch(:user), accepted.accepted_user
                assert_equal Time.current, accepted.accepted_at

                cancelled = insert_invite(
                    context,
                    email: "cancelled-transition@example.com"
                )
                cancelled.cancel!

                assert cancelled.cancelled?
                assert_equal Time.current, cancelled.cancelled_at

                expired = insert_invite(
                    context,
                    email: "expired-transition@example.com"
                )
                expired.expire!

                assert expired.expired?
                assert expired.resendable?

                expired.resend!

                assert expired.pending?
                refute expired.resendable?
                assert_equal Invite.expiration_period.from_now, expired.expires_at
            end
        end

        private

        def insert_account_context(identifier)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "#{identifier}-account@example.com",
                name: "Account #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            shield_account_id = LesliShield::Account.insert_all!([{
                account_id: account_id,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            user_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "UID-#{identifier}",
                email: "#{identifier}-owner@example.com",
                encrypted_password: "",
                active: true,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            {
                shield_account: LesliShield::Account.find(shield_account_id),
                user: Lesli::User.find(user_id)
            }
        end

        def insert_invite(
            context,
            email:,
            status: :pending,
            expires_at: 1.day.from_now
        )
            timestamp = Time.current
            invite_id = Invite.insert_all!([{
                account_id: context.fetch(:shield_account).id,
                invited_by_id: context.fetch(:user).id,
                email: email,
                status: Invite.statuses.fetch(status.to_s),
                expires_at: expires_at,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Invite.find(invite_id)
        end

        def assert_equal_ids(expected_records, actual_scope)
            assert_equal expected_records.map(&:id).sort, actual_scope.ids.sort
        end
    end
end
