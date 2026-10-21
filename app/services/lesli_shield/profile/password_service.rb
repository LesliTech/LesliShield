module LesliShield
    module Profile
        class PasswordService < Lesli::ApplicationLesliService
            def initialize(user)
                super(user)
                self.resource = user
            end

            def update(params, current_session_id: nil)
                password_updated = false

                resource.transaction do
                    password_updated = resource.update_with_password(params)

                    if password_updated
                        clear_password_expiration
                        revoke_other_sessions(current_session_id)
                    end
                end

                unless password_updated
                    resource.errors.full_messages.each { |message| error(message) }
                end

                self
            end

            private

            def clear_password_expiration
                return unless resource.has_attribute?(:password_expiration_at)
                return if resource.password_expiration_at.nil?

                resource.update_column(:password_expiration_at, nil)
            end

            def revoke_other_sessions(current_session_id)
                return if current_session_id.blank?

                current_session = resource.sessions.find_by(id: current_session_id)
                return unless current_session

                resource.sessions.where.not(id: current_session.id).destroy_all
            end
        end
    end
end
