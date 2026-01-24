module LesliShield
    class User::Role < ApplicationRecord
        self.table_name = 'lesli_shield_user_roles'
        belongs_to :user
        belongs_to :role, class_name: "Lesli::Role"
        has_many :roles
    end
end
