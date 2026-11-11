# frozen_string_literal: true

require "test_helper"
require "cgi"
require "uri"

module LesliShield
    class AuditedInvitationServiceForTest < InvitationService
        attr_accessor :failing_audit_event
        attr_reader :audit_events

        def initialize(current_user)
            super
            @audit_events = []
        end

        private

        def record_audit_event!(operation, invitation, actor:)
            @audit_events << {
                operation: operation.to_s,
                invitation: invitation,
                actor: actor
            }

            if operation.to_s == failing_audit_event.to_s
                raise "Audit persistence failed"
            end
        end
    end

    class InvitationDeliveryErrorReporterForTest
        attr_reader :error, :options

        def report(error, **options)
            @error = error
            @options = options
        end
    end

    class FailingInvitationDeliveryJobForTest < InvitationDeliveryJob
        attr_reader :failed_event

        private

        def deliver_invitation(_invitation, _acceptance_url)
            raise "SMTP delivery failed"
        end

        def record_delivery_failure_event(invitation, actor)
            @failed_event = {
                operation: "invitation_delivery_failed",
                invitation: invitation,
                actor: actor
            }
        end
    end

    class SuccessfulInvitationDeliveryJobForTest < InvitationDeliveryJob
        attr_reader :successful_event

        private

        def deliver_invitation(_invitation, _acceptance_url)
        end

        def record_delivery_success(operation, invitation:, actor:)
            @successful_event = {
                operation: operation,
                invitation: invitation,
                actor: actor
            }
        end
    end

    class InvitationServiceTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        setup do
            clear_enqueued_jobs
            clear_performed_jobs
            ActionMailer::Base.deliveries.clear
            use_local_lesli_assets_views

            @context = insert_account_context
            @service = InvitationService.new(@context.fetch(:owner))
        end

        test "creates and queues a normalized invitation without creating a user" do
            invited_email = " New.Person.#{SecureRandom.hex(4)}@Example.COM "

            assert_no_difference -> { Lesli::User.count } do
                assert_enqueued_jobs 1, only: InvitationDeliveryJob do
                    @invitation = @service.create_and_send!(
                        email: invited_email,
                        full_name: "New Person",
                        notes: "Welcome to the team.",
                        role_id: @context.fetch(:target_role).id
                    )
                end
            end

            assert @invitation.persisted?
            assert @invitation.pending?
            assert_equal invited_email.strip.downcase, @invitation.email
            assert_equal @context.fetch(:shield_account), @invitation.account
            assert_equal @context.fetch(:owner), @invitation.invited_by
            assert_equal @context.fetch(:target_role), @invitation.role
            assert_equal "Welcome to the team.", @invitation.notes
            assert @invitation.sent_at.present?
            assert @invitation.expires_at.future?
        end

        test "delivers a signed acceptance link after the transaction commits" do
            invitation = nil

            perform_enqueued_jobs do
                invitation = @service.create_and_send!(
                    email: unique_email("mail"),
                    notes: "We would love to have you on the team.",
                    role_id: @context.fetch(:target_role).id
                )
            end

            mail = ActionMailer::Base.deliveries.last
            assert_equal [invitation.email], mail.to
            assert_equal I18n.t("lesli_shield.invites.mailer_subject"), mail.subject

            html = mail.body.decoded
            acceptance_link = html.match(
                /href="([^"]*invitation_token=[^"]+)"/
            )
            assert acceptance_link
            acceptance_url = CGI.unescapeHTML(
                acceptance_link[1]
            )
            token = Rack::Utils.parse_query(URI(acceptance_url).query)
                .fetch("invitation_token")

            assert_includes html, invitation.account.account.name
            assert_includes html, invitation.invited_by.full_name
            assert_includes html, invitation.notes
            assert_includes html, I18n.l(invitation.expires_at, format: :long)
            assert_includes html,
                I18n.t("lesli_shield.invites.mailer_ignore_notice")
            assert_equal invitation, @service.invitation_from_token!(token)
        end

        test "limits signed links to seven days" do
            invitation = insert_invitation(
                email: unique_email("token-lifetime"),
                expires_at: 30.days.from_now
            )
            acceptance_url = @service.signed_acceptance_url(invitation)
            token = Rack::Utils.parse_query(URI(acceptance_url).query)
                .fetch("invitation_token")

            travel 7.days + 1.second do
                assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
                    @service.invitation_from_token!(token)
                end
            end
        end

        test "rejects a manipulated signed invitation token" do
            invitation = insert_invitation(email: unique_email("tampered"))
            token = acceptance_token(invitation)
            replacement = token.end_with?("a") ? "b" : "a"
            manipulated_token = "#{token[0...-1]}#{replacement}"

            assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
                @service.invitation_from_token!(manipulated_token)
            end
        end

        test "rejects a token when invitation timestamps are inconsistent" do
            invitation = insert_invitation(email: unique_email("terminal"))
            token = acceptance_token(invitation)
            invitation.update_column(:cancelled_at, Time.current)

            assert_raises(ActiveRecord::RecordInvalid) do
                @service.invitation_from_token!(token)
            end
        end

        test "rejects a token after the account is suspended" do
            invitation = insert_invitation(email: unique_email("account"))
            token = acceptance_token(invitation)
            @context.fetch(:account).update!(status: :suspended)

            assert_no_difference -> { Lesli::User.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    @service.accept!(
                        token: token,
                        user_attributes: valid_user_attributes
                    )
                end
            end
        end

        test "rejects a token after its role is disabled or removed" do
            disabled_role_invitation = insert_invitation(
                email: unique_email("disabled-role")
            )
            disabled_role_token = acceptance_token(disabled_role_invitation)
            @context.fetch(:target_role).update!(active: false)

            assert_raises(ActiveRecord::RecordInvalid) do
                @service.invitation_from_token!(disabled_role_token)
            end

            @context.fetch(:target_role).update!(active: true)
            missing_role_invitation = insert_invitation(
                email: unique_email("missing-role")
            )
            missing_role_token = acceptance_token(missing_role_invitation)
            missing_role_invitation.update_column(:role_id, nil)

            assert_raises(ActiveRecord::RecordInvalid) do
                @service.invitation_from_token!(missing_role_token)
            end
        end

        test "rejects members and roles that the inviter cannot assign" do
            assert_no_difference -> { Invite.count } do
                assert_no_enqueued_jobs do
                    assert_raises(ActiveRecord::RecordInvalid) do
                        @service.create_and_send!(
                            email: @context.fetch(:owner).email,
                            role_id: @context.fetch(:target_role).id
                        )
                    end
                end
            end

            elevated_role = insert_role(
                name: "elevated",
                permission_level: 101
            )

            assert_no_difference -> { Invite.count } do
                assert_raises(ActiveRecord::RecordNotFound) do
                    @service.create_and_send!(
                        email: unique_email("elevated"),
                        role_id: elevated_role.id
                    )
                end
            end
        end

        test "rejects a role belonging to another account" do
            foreign_context = insert_account_context

            assert_no_difference -> { Invite.count } do
                assert_no_enqueued_jobs do
                    assert_raises(ActiveRecord::RecordNotFound) do
                        @service.create_and_send!(
                            email: unique_email("foreign-role"),
                            role_id: foreign_context.fetch(:target_role).id
                        )
                    end
                end
            end
        end

        test "resends only expired invitations and renews their expiration" do
            invitation = insert_invitation(
                email: unique_email("expired"),
                status: :expired,
                expires_at: 1.hour.ago
            )

            travel_to Time.zone.local(2026, 11, 11, 12, 0, 0) do
                assert_enqueued_jobs 1, only: InvitationDeliveryJob do
                    @service.resend!(invitation)
                end

                invitation.reload
                assert invitation.pending?
                assert_equal Invite.expiration_period.from_now,
                    invitation.expires_at
                assert_equal Time.current, invitation.sent_at
            end

            assert_raises(Invite::InvalidStatusTransition) do
                @service.resend!(invitation)
            end
        end

        test "cancels a pending invitation without sending another email" do
            invitation = insert_invitation(email: unique_email("cancel"))

            assert_no_enqueued_jobs do
                @service.cancel!(invitation)
            end

            invitation.reload
            assert invitation.cancelled?
            assert invitation.cancelled_at.present?
        end

        test "accepts once by creating confirming and assigning the invited user" do
            invitation = insert_invitation(email: unique_email("accept"))
            token = acceptance_token(invitation)

            assert_no_difference -> { Lesli::Account.count } do
                assert_difference -> { Lesli::User.count }, 1 do
                    assert_difference -> { User::Role.count }, 1 do
                        @accepted_user = @service.accept!(
                            token: token,
                            user_attributes: valid_user_attributes
                        )
                    end
                end
            end

            invitation.reload
            assert invitation.accepted?
            assert_equal @accepted_user, invitation.accepted_user
            assert invitation.accepted_at.present?
            assert_equal @context.fetch(:account), @accepted_user.account
            assert_equal [@context.fetch(:target_role)], @accepted_user.roles.to_a
            assert @accepted_user.confirmed?
            assert_nil @accepted_user.confirmation_token
            assert_nil @accepted_user.confirmation_sent_at

            assert_no_difference -> { Lesli::User.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    @service.accept!(
                        token: token,
                        user_attributes: valid_user_attributes
                    )
                end
            end
        end

        test "records cancellation and acceptance inside their transactions" do
            service = AuditedInvitationServiceForTest.new(
                @context.fetch(:owner)
            )

            cancelled_invitation = insert_invitation(
                email: unique_email("audited-cancel")
            )
            service.cancel!(cancelled_invitation)
            accepted_invitation = insert_invitation(
                email: unique_email("audited-accept")
            )
            accepted_user = service.accept!(
                token: acceptance_token(accepted_invitation),
                user_attributes: valid_user_attributes
            )

            assert_equal(
                %w[
                    invitation_cancelled
                    invitation_accepted
                ],
                service.audit_events.pluck(:operation)
            )
            assert_equal cancelled_invitation,
                service.audit_events.first.fetch(:invitation)
            assert_equal accepted_user,
                service.audit_events.last.fetch(:actor)
        end

        test "audits sent and resent only after successful delivery" do
            invitation = insert_invitation(
                email: unique_email("delivery-success")
            )

            %w[invitation_sent invitation_resent].each do |operation|
                job = SuccessfulInvitationDeliveryJobForTest.new(
                    invitation.id,
                    "https://example.test/invitation",
                    operation,
                    @context.fetch(:owner).id
                )

                job.perform_now

                assert_equal operation,
                    job.successful_event.fetch(:operation)
                assert_equal invitation,
                    job.successful_event.fetch(:invitation)
                assert_equal @context.fetch(:owner),
                    job.successful_event.fetch(:actor)
            end
        end

        test "rolls back the complete acceptance when its audit event fails" do
            service = AuditedInvitationServiceForTest.new(
                @context.fetch(:owner)
            )
            service.failing_audit_event = "invitation_accepted"
            invitation = insert_invitation(
                email: unique_email("audit-rollback")
            )
            original_user_role_count = User::Role.count

            assert_no_difference -> { Lesli::User.count } do
                error = assert_raises(RuntimeError) do
                    service.accept!(
                        token: acceptance_token(invitation),
                        user_attributes: valid_user_attributes
                    )
                end

                assert_equal "Audit persistence failed", error.message
            end

            assert_equal original_user_role_count, User::Role.count
            invitation.reload
            assert invitation.pending?
            assert_nil invitation.accepted_user
            assert_nil invitation.accepted_at
        end

        test "audits and reports a delivery failure without changing its message" do
            invitation = insert_invitation(
                email: unique_email("delivery-failure")
            )
            reporter = InvitationDeliveryErrorReporterForTest.new
            job = FailingInvitationDeliveryJobForTest.new(
                invitation.id,
                "https://example.test/invitation",
                "invitation_sent",
                @context.fetch(:owner).id
            )
            Rails.error.subscribe(reporter)

            begin
                error = assert_raises(RuntimeError) { job.perform_now }
            ensure
                Rails.error.unsubscribe(reporter)
            end

            assert_equal "SMTP delivery failed", error.message
            assert_equal "invitation_delivery_failed",
                job.failed_event.fetch(:operation)
            assert_equal invitation, job.failed_event.fetch(:invitation)
            assert_equal invitation.invited_by,
                job.failed_event.fetch(:actor)
            assert_equal error, reporter.error
            assert_equal false, reporter.options.fetch(:handled)
            assert_equal(
                {
                    job: FailingInvitationDeliveryJobForTest.name,
                    operation: "invitation_delivery_failed",
                    invitation_id: invitation.id,
                    stage: "delivery"
                },
                reporter.options.fetch(:context)
            )
        end

        test "recovers the same unconfirmed user only during acceptance" do
            email = unique_email("recover")
            recoverable_user = Lesli::User.new(
                email: email,
                password: "old-password-123",
                password_confirmation: "old-password-123"
            )
            recoverable_user.skip_confirmation_notification!
            recoverable_user.save!

            invitation = insert_invitation(email: email)

            assert_no_difference -> { Lesli::User.count } do
                accepted_user = @service.accept!(
                    token: acceptance_token(invitation),
                    user_attributes: valid_user_attributes
                )

                assert_equal recoverable_user.id, accepted_user.id
            end

            recoverable_user.reload
            assert_equal @context.fetch(:account), recoverable_user.account
            assert_equal [@context.fetch(:target_role)], recoverable_user.roles.to_a
            assert recoverable_user.confirmed?
        end

        test "rolls back user role and invitation when acceptance is invalid" do
            invitation = insert_invitation(email: unique_email("rollback"))
            original_user_role_count = User::Role.count

            assert_no_difference -> { Lesli::User.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    @service.accept!(
                        token: acceptance_token(invitation),
                        user_attributes: valid_user_attributes.merge(
                            password_confirmation: "different-password"
                        )
                    )
                end
            end

            assert_equal original_user_role_count, User::Role.count
            invitation.reload
            assert invitation.pending?
            assert_nil invitation.accepted_user
            assert_nil invitation.accepted_at
        end

        private

        def use_local_lesli_assets_views
            views_path = Pathname.new(__dir__).join(
                "../../../../../gems/LesliAssets/app/views"
            ).expand_path
            return unless views_path.directory?
            return if InvitationMailer.view_paths.any? do |path|
                path.to_path == views_path.to_s
            end

            InvitationMailer.prepend_view_path(views_path)
        end

        def insert_account_context
            identifier = SecureRandom.hex(6)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "account-#{identifier}@example.com",
                name: "Invitation account #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            shield_account_id = Account.insert_all!([{
                account_id: account_id,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            owner_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "OWNER-#{identifier}",
                email: "owner-#{identifier}@example.com",
                first_name: "Ada",
                last_name: "Inviter",
                encrypted_password: "",
                active: true,
                confirmed_at: timestamp,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            owner_role = insert_role(
                account_id: account_id,
                name: "owner-#{identifier}",
                permission_level: 100
            )
            target_role = insert_role(
                account_id: account_id,
                name: "member-#{identifier}",
                permission_level: 50
            )

            User::Role.insert_all!([{
                user_id: owner_id,
                role_id: owner_role.id,
                created_at: timestamp,
                updated_at: timestamp
            }])

            {
                account: Lesli::Account.find(account_id),
                shield_account: Account.find(shield_account_id),
                owner: Lesli::User.find(owner_id),
                owner_role: owner_role,
                target_role: target_role
            }
        end

        def insert_role(
            account_id: @context&.fetch(:account)&.id,
            name:,
            permission_level:,
            active: true
        )
            timestamp = Time.current
            role_id = Lesli::Role.insert_all!([{
                account_id: account_id,
                name: name,
                code: "#{name}-#{SecureRandom.hex(3)}",
                permission_level: permission_level,
                active: active,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Lesli::Role.find(role_id)
        end

        def insert_invitation(email:, status: :pending, expires_at: 1.day.from_now)
            timestamp = Time.current
            invitation_id = Invite.insert_all!([{
                account_id: @context.fetch(:shield_account).id,
                invited_by_id: @context.fetch(:owner).id,
                role_id: @context.fetch(:target_role).id,
                email: email,
                status: Invite.statuses.fetch(status.to_s),
                expires_at: expires_at,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Invite.find(invitation_id)
        end

        def acceptance_token(invitation)
            invitation.signed_id(
                purpose: InvitationService::ACCEPTANCE_PURPOSE,
                expires_in: 1.day
            )
        end

        def valid_user_attributes
            {
                first_name: "Invited",
                last_name: "Person",
                telephone: "+502 5555 5555",
                password: "password-123",
                password_confirmation: "password-123"
            }
        end

        def unique_email(prefix)
            "#{prefix}-#{SecureRandom.hex(6)}@example.com"
        end
    end
end
