# frozen_string_literal: true

module LesliShield
    class InvitationMailer < Lesli::ApplicationLesliMailer
        default from: -> { configured_sender }

        def invitation(invitation, acceptance_url)
            @invitation = invitation
            @acceptance_url = acceptance_url

            mail(
                to: invitation.email,
                subject: I18n.t("lesli_shield.invites.mailer_subject"),
                template_path: "lesli_shield/invitation_mailer",
                template_name: "invitation"
            )
        end

        private

        def configured_sender
            sender = Devise.mailer_sender
            sender = sender.call(:user) if sender.respond_to?(:call)

            sender.presence ||
                Rails.application.config.action_mailer.default_options&.dig(:from).presence ||
                "no-reply@lesli.dev"
        end
    end
end
