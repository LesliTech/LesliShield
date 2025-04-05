module LesliShield
    class User < ::Lesli::User
        has_many :lesli_activities, as: :recordable
    end
end
