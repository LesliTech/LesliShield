module LesliShield
    class ProfileService < Lesli::ApplicationLesliService
        def initialize(user)
            super(user)
            self.resource = user
        end

        def show
            resource
        end

        def update(params)
            resource.assign_attributes(params)
            resource.alias = resource.full_name_initials if resource.alias.blank?

            unless resource.save
                error(resource.errors.full_messages.to_sentence)
                return self
            end

            self
        end
    end
end
