=begin

Lesli

Copyright (c) 2026, Lesli Technologies, S. A.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see http://www.gnu.org/licenses/.

Lesli · Ruby on Rails SaaS Development Framework.

Made with ♥ by LesliTech
Building a better future, one line of code at a time.

@contact  hello@lesli.tech
@website  https://www.lesli.tech
@license  GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html

// · ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~
// · 
=end

module LesliShield
    class UsersController < ApplicationController
        before_action :set_user, only: %i[ show edit update destroy ]

        # GET /users
        def index
            @users = respond_as_pagination(Lesli::UserService.new(current_user, query).index(params))
        end

        # GET /users/1
        def show
            # @activities = @user.result.activities.order(id: :desc).map { |a| {
            #     id: a[:id],
            #     title: a[:title].titleize,
            #     description: a[:description],
            #     date: Date2.new(a[:created_at]).date_words
            # }}
            @activities = []
            @sessions = @user.result.sessions
            @user = @user.show
        end

        # GET /users/new
        def new
            @user = User.new
        end

        # GET /users/1/edit
        def edit
        end

        # POST /users
        def create
            @user = User.new(user_params)

            if @user.save
                respond_with_stream(
                    stream_notification_success('User was successfully created.')
                )
            else
                respond_with_stream(
                    stream_notification_danger(@user.errors.full_messages.to_sentence)
                )
            end
        end

        # PATCH/PUT /users/1
        def update

            # update the user information
            @user.update(user_params)

            # check saved
            if @user.successful?
                respond_with_lesli(
                    :turbo => stream_notification_success("User updated successfully!")
                )
            else 
                respond_with_lesli(
                    :turbo => stream_notification_danger(@user.errors_as_sentence)
                )
            end
        end

        # DELETE /users/1
        def destroy
            @user.destroy!
            redirect_to(users_path, notice: "User was successfully destroyed.", status: :see_other)
        end

        private

        def set_user

            # Search for the user
            @user = Lesli::UserService.new(current_user).find(params[:id])

            # check if the user trully exists
            return respond_with_not_found unless @user.found?
        end

        # Only allow a list of trusted parameters through.
        def user_params
            params.require(:user).permit(
                :active,
                :email,
                :alias,
                :title,
                :roles_id,
                :first_name,
                :last_name,
                :telephone
            )
        end
    end
end
