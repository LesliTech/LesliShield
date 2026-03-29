Rails.application.routes.draw do
    mount Lesli::Engine => "/lesli"
    mount LesliShield::Engine => "/lesli_shield"
end
