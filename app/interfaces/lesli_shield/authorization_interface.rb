module LesliShield
    module AuthorizationInterface

        # Check if current_user has privileges to complete this request
        def authorize_request

            # check if user has access to the requested controller
            # this search is over all the privileges for all the roles of the users
            granted = current_user.has_privileges_for?(params[:controller], params[:action])


            # get the path to which the user is limited to
            limited_path = false# current_user.has_role_limited_to_path?

            # to redirect to the limited path we must check:
            #   limited_path must not to be nil or empty string ("")
            #   limited_path must not to be equal to the current path (to avoid a loop)
            #   request must not to be AJAX
            #   request must be for show or index views
            if  !limited_path.blank? and
                !(limited_path == request.original_fullpath) and
                !(request[:format] == "json") and
                ["show", "index"].include?(params[:action])

                return redirect_to(limited_path)
            end

            # privilege for object not found
            if granted.blank?
                current_user.activities.create({ title: "privilege_not_found", description: request.path })
                return respond_with_unauthorized({ controller: params[:controller], privilege: params[:action] })
            end

            unless granted
                current_user.activities.create({ title: "privilege_not_granted", description: request.path })
                return respond_with_unauthorized({ controller: params[:controller], privilege: params[:action] })
            end
        end
    end
end
