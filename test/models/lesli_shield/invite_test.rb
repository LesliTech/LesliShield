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
        end

        test "accepted and cancelled invitations are terminal" do
            accepted = Invite.new(email: "accepted@example.com", status: :accepted)
            cancelled = Invite.new(email: "cancelled@example.com", status: :cancelled)

            assert_raises(Invite::InvalidStatusTransition) { accepted.resend! }
            assert_raises(Invite::InvalidStatusTransition) { cancelled.resend! }
        end
    end
end
