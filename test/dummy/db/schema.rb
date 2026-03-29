# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 801120110) do
  create_table "lesli_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email", null: false
    t.string "name"
    t.string "region", default: "america"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["deleted_at"], name: "index_lesli_accounts_on_deleted_at"
    t.index ["email"], name: "index_lesli_accounts_on_email", unique: true
    t.index ["user_id"], name: "index_lesli_accounts_on_user_id"
  end

  create_table "lesli_resources", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "engine"
    t.string "identifier"
    t.string "label"
    t.integer "parent_id"
    t.string "route"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_lesli_resources_on_deleted_at"
    t.index ["parent_id"], name: "index_lesli_resources_on_parent_id"
  end

  create_table "lesli_roles", force: :cascade do |t|
    t.integer "account_id"
    t.boolean "active"
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "deployed_at"
    t.string "description"
    t.boolean "isolated", default: false
    t.datetime "modified_at"
    t.string "name"
    t.string "path_default"
    t.boolean "path_limited"
    t.integer "permission_level", default: 10
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lesli_roles_on_account_id"
    t.index ["deleted_at"], name: "index_lesli_roles_on_deleted_at"
  end

  create_table "lesli_shield_accounts", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.datetime "enabled_at", precision: nil
    t.string "name"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lesli_shield_accounts_on_account_id"
    t.index ["deleted_at"], name: "index_lesli_shield_accounts_on_deleted_at"
  end

  create_table "lesli_shield_invites", force: :cascade do |t|
    t.integer "account_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email", null: false
    t.datetime "expired_at"
    t.string "full_name"
    t.text "notes"
    t.datetime "sent_at"
    t.integer "status"
    t.string "telephone"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["account_id"], name: "index_lesli_shield_invites_on_account_id"
    t.index ["deleted_at"], name: "index_lesli_shield_invites_on_deleted_at"
    t.index ["expired_at"], name: "index_lesli_shield_invites_on_expired_at"
    t.index ["sent_at"], name: "index_lesli_shield_invites_on_sent_at"
    t.index ["status"], name: "index_lesli_shield_invites_on_status"
    t.index ["user_id"], name: "index_lesli_shield_invites_on_user_id"
  end

  create_table "lesli_shield_role_actions", force: :cascade do |t|
    t.integer "action_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "role_id"
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "role_actions_resources"
    t.index ["deleted_at"], name: "index_lesli_shield_role_actions_on_deleted_at"
    t.index ["role_id", "action_id"], name: "index_role_actions_on_role_and_action", unique: true
    t.index ["role_id"], name: "index_lesli_shield_role_actions_on_role_id"
  end

  create_table "lesli_shield_role_privileges", force: :cascade do |t|
    t.string "action"
    t.boolean "active"
    t.string "controller"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "role_id"
    t.datetime "updated_at", null: false
    t.index ["controller", "action", "role_id"], name: "shield_role_privileges_index", unique: true
    t.index ["deleted_at"], name: "index_lesli_shield_role_privileges_on_deleted_at"
    t.index ["role_id"], name: "index_lesli_shield_role_privileges_on_role_id"
  end

  create_table "lesli_shield_user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.integer "role_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["deleted_at"], name: "index_lesli_shield_user_roles_on_deleted_at"
    t.index ["role_id"], name: "index_lesli_shield_user_roles_on_role_id"
    t.index ["user_id"], name: "index_lesli_shield_user_roles_on_user_id"
  end

  create_table "lesli_shield_user_sessions", force: :cascade do |t|
    t.string "agent_browser"
    t.string "agent_os"
    t.string "agent_platform"
    t.string "agent_version"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.datetime "expiration_at", precision: nil
    t.datetime "last_used_at", precision: nil
    t.string "remote"
    t.string "session_source"
    t.string "session_token"
    t.datetime "updated_at", null: false
    t.integer "usage_count"
    t.integer "user_id"
    t.index ["deleted_at"], name: "index_lesli_shield_user_sessions_on_deleted_at"
    t.index ["expiration_at"], name: "index_lesli_shield_user_sessions_on_expiration_at"
    t.index ["user_id"], name: "index_lesli_shield_user_sessions_on_user_id"
  end

  create_table "lesli_shield_user_shortcuts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id"
    t.index ["user_id"], name: "index_lesli_shield_user_shortcuts_on_user_id"
  end

  create_table "lesli_shield_user_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "expiration_at"
    t.string "name", null: false
    t.string "source", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["deleted_at"], name: "index_lesli_shield_user_tokens_on_deleted_at"
    t.index ["expiration_at"], name: "index_lesli_shield_user_tokens_on_expiration_at"
    t.index ["token"], name: "index_lesli_shield_user_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_lesli_shield_user_tokens_on_user_id"
  end

  create_table "lesli_users", force: :cascade do |t|
    t.integer "account_id"
    t.boolean "active", default: true, null: false
    t.string "alias"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.datetime "deleted_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.datetime "locked_until"
    t.datetime "password_expiration_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "salutation"
    t.integer "sign_in_count", default: 0, null: false
    t.string "telephone"
    t.datetime "telephone_confirmation_sent_at"
    t.string "telephone_confirmation_token"
    t.datetime "telephone_confirmed_at"
    t.string "title"
    t.string "uid", null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lesli_users_on_account_id"
    t.index ["confirmation_token"], name: "index_lesli_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_lesli_users_on_deleted_at"
    t.index ["email"], name: "index_lesli_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_lesli_users_on_reset_password_token", unique: true
    t.index ["uid"], name: "index_lesli_users_on_uid", unique: true
    t.index ["unlock_token"], name: "index_lesli_users_on_unlock_token", unique: true
  end

  add_foreign_key "lesli_accounts", "lesli_users", column: "user_id"
  add_foreign_key "lesli_resources", "lesli_resources", column: "parent_id"
  add_foreign_key "lesli_roles", "lesli_accounts", column: "account_id"
  add_foreign_key "lesli_shield_accounts", "lesli_accounts", column: "account_id"
  add_foreign_key "lesli_shield_invites", "lesli_shield_accounts", column: "account_id"
  add_foreign_key "lesli_shield_invites", "lesli_users", column: "user_id"
  add_foreign_key "lesli_shield_role_actions", "lesli_resources", column: "action_id"
  add_foreign_key "lesli_shield_role_actions", "lesli_roles", column: "role_id"
  add_foreign_key "lesli_shield_role_privileges", "lesli_roles", column: "role_id"
  add_foreign_key "lesli_shield_user_roles", "lesli_roles", column: "role_id"
  add_foreign_key "lesli_shield_user_roles", "lesli_users", column: "user_id"
  add_foreign_key "lesli_shield_user_sessions", "lesli_users", column: "user_id"
  add_foreign_key "lesli_shield_user_shortcuts", "lesli_users", column: "user_id"
  add_foreign_key "lesli_shield_user_tokens", "lesli_users", column: "user_id"
  add_foreign_key "lesli_users", "lesli_accounts", column: "account_id"
end
