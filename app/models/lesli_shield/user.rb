module LesliShield
    # Namespace for Shield-owned records associated with Lesli::User, such as
    # User::Role and User::Session. The authenticatable model remains
    # Lesli::User; defining a second ActiveRecord subclass for the same table
    # causes association type mismatches and can confuse Devise mappings.
    module User
    end
end
