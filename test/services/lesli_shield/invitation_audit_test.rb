# frozen_string_literal: true

require "test_helper"

module LesliShield
    class InvitationAuditTest < ActiveSupport::TestCase
        class AuditActor
            attr_reader :attributes

            def log(**attributes)
                @attributes = attributes
            end
        end

        test "records the exact invitation event vocabulary" do
            invitation = Invite.new
            actor = AuditActor.new

            InvitationAudit.record!(
                :invitation_sent,
                invitation: invitation,
                actor: actor,
                source: InvitationService
            )

            assert_equal "invitation_sent", actor.attributes[:operation]
            assert_equal "invitation_sent", actor.attributes[:action]
            assert_equal LesliShield, actor.attributes[:engine]
            assert_equal InvitationService, actor.attributes[:source]
            assert_equal invitation, actor.attributes[:subject]
            assert_equal(
                "Invitation delivered",
                actor.attributes[:description]
            )
        end

        test "rejects unknown events and missing actors" do
            invitation = Invite.new

            assert_raises(KeyError) do
                InvitationAudit.record!(
                    :unknown_event,
                    invitation: invitation,
                    actor: AuditActor.new,
                    source: InvitationService
                )
            end

            assert_raises(ArgumentError) do
                InvitationAudit.record!(
                    :invitation_accepted,
                    invitation: invitation,
                    actor: nil,
                    source: InvitationService
                )
            end
        end
    end
end
