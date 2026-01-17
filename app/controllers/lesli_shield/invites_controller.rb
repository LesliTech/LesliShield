module LesliShield
    class InvitesController < ApplicationController
        before_action :set_invite, only: %i[ show edit update destroy ]

        # GET /invites
        def index
            @invites = respond_as_pagination(LesliShield::InviteService.new(current_user, query).index(params))
        end

        # GET /invites/1
        def show
        end

        # GET /invites/new
        def new
            @invite = Invite.new
        end

        # GET /invites/1/edit
        def edit
        end

        # POST /invites
        def create
            @invite = current_user.account.shield.invites.new(invite_params)
            @invite.user = current_user
            if @invite.save
                log(
                    subject: @invite,
                    description: "Invitation created successfully"
                )
                success("Invite was successfully created.")
                respond_with_stream(
                    stream_redirection(invite_path(@invite)),
                ) 
            else
                respond_with_stream(
                    stream_notification_danger(@invite.errors.full_messages.to_sentence),
                )
            end
        end

        # PATCH/PUT /invites/1
        def update
            if @invite.update(invite_params)
                log(
                    subject: @invite,
                    description: "Invitation updated successfully"
                )
                respond_with_stream(
                    stream_notification_success("Invite was successfully updated.")
                ) 
            else
                respond_with_stream(
                    stream_notification_danger(@invite.errors.full_messages.to_sentence)
                ) 
            end
        end

        # DELETE /invites/1
        def destroy
        @invite.destroy!
        redirect_to invites_path, notice: "Invite was successfully destroyed.", status: :see_other
        end

        private
        # Use callbacks to share common setup or constraints between actions.
        def set_invite
            @invite = Invite.find(params.expect(:id))
        end

        # Only allow a list of trusted parameters through.
        def invite_params
            params.require(:invite).permit(:email, :full_name, :telephone, :notes, :status)
        end
    end
end
