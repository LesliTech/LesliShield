# frozen_string_literal: true

module LesliShield
    class InvitationMailer < Lesli::ApplicationLesliMailer
        default from: -> { configured_sender }

        def account_invitation(invitation, acceptance_url)
            account = invitation.account.account
            invited_by = invitation.invited_by
            inviter_name = invited_by.full_name.to_s.strip.presence ||
                invited_by.email

            email_params = {
                user: invited_by,
                title: I18n.t("lesli_shield.invites.mailer_title"),
                description: I18n.t(
                    "lesli_shield.invites.mailer_description",
                    account: account.name
                ),
                invited_by: I18n.t(
                    "lesli_shield.invites.mailer_invited_by",
                    inviter: inviter_name
                ),
                expiration: I18n.t(
                    "lesli_shield.invites.mailer_expiration",
                    expiration: I18n.l(invitation.expires_at, format: :long)
                ),
                action: I18n.t("lesli_shield.invites.mailer_action"),
                ignore_notice: I18n.t(
                    "lesli_shield.invites.mailer_ignore_notice"
                ),
                message: invitation.notes.to_s.strip.presence,
                acceptance_url: acceptance_url
            }

            @params = @params.merge(email_params)
            build_app_from_params(email_params)

            mail(
                to: invitation.email,
                subject: I18n.t("lesli_shield.invites.mailer_subject"),
                template_path: "lesli_shield/invitation_mailer",
                template_name: "account_invitation"
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
