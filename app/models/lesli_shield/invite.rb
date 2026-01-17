module LesliShield
    class Invite < ApplicationRecord
        belongs_to :account
        belongs_to :user, class_name: "Lesli::User"

        validates :email, presence: true, on: :create

        before_create :before_create_invite

        enum :status, { 
            created: 0, 
            accepted: 1, 
            cancelled: 2,
            sent: 5, 
            requested: 6
        }

        private 

        def before_create_invite
            self.status = :created
        end
    end
end
