module LesliShield
    class Activity < ApplicationRecord
        belongs_to :recordable, polymorphic: true
        belongs_to :user, class_name: "LesliUser"
    end
end
