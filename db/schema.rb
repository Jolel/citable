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

ActiveRecord::Schema[8.1].define(version: 2026_04_18_000009) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "locale", default: "es-MX", null: false
    t.string "name", null: false
    t.string "plan", default: "free", null: false
    t.string "subdomain", null: false
    t.string "timezone", default: "America/Mexico_City", null: false
    t.datetime "updated_at", null: false
    t.integer "whatsapp_quota_used", default: 0, null: false
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true
  end

  create_table "bookings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "address"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "deposit_state", default: "not_required", null: false
    t.datetime "ends_at", null: false
    t.string "google_event_id"
    t.bigint "recurrence_rule_id"
    t.bigint "service_id", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false, comment: "staff member assigned"
    t.index ["account_id", "starts_at"], name: "index_bookings_on_account_id_and_starts_at"
    t.index ["account_id"], name: "index_bookings_on_account_id"
    t.index ["customer_id"], name: "index_bookings_on_customer_id"
    t.index ["recurrence_rule_id"], name: "index_bookings_on_recurrence_rule_id"
    t.index ["service_id"], name: "index_bookings_on_service_id"
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["user_id", "starts_at"], name: "index_bookings_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_bookings_on_user_id"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "custom_fields", default: {}, null: false
    t.string "name", null: false
    t.text "notes"
    t.string "phone", null: false
    t.text "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["account_id", "phone"], name: "index_customers_on_account_id_and_phone"
    t.index ["account_id"], name: "index_customers_on_account_id"
    t.index ["custom_fields"], name: "index_customers_on_custom_fields", using: :gin
    t.index ["tags"], name: "index_customers_on_tags", using: :gin
  end

  create_table "message_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "body", null: false
    t.bigint "booking_id"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.string "direction", null: false
    t.string "external_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_message_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_message_logs_on_account_id"
    t.index ["booking_id"], name: "index_message_logs_on_booking_id"
    t.index ["customer_id"], name: "index_message_logs_on_customer_id"
    t.index ["external_id"], name: "index_message_logs_on_external_id"
  end

  create_table "recurrence_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.date "ends_on"
    t.string "frequency", null: false
    t.integer "interval", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_recurrence_rules_on_account_id"
  end

  create_table "reminder_schedules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "booking_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "scheduled_for", null: false
    t.datetime "sent_at"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_reminder_schedules_on_account_id"
    t.index ["booking_id", "kind"], name: "index_reminder_schedules_on_booking_id_and_kind", unique: true
    t.index ["booking_id"], name: "index_reminder_schedules_on_booking_id"
    t.index ["scheduled_for"], name: "index_reminder_schedules_on_scheduled_for"
  end

  create_table "services", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "deposit_amount_cents", default: 0, null: false
    t.integer "duration_minutes", default: 60, null: false
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "requires_address", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_services_on_account_id_and_name"
    t.index ["account_id"], name: "index_services_on_account_id"
  end

  create_table "staff_availabilities", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.time "end_time", null: false
    t.time "start_time", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_staff_availabilities_on_account_id"
    t.index ["user_id", "day_of_week"], name: "index_staff_availabilities_on_user_id_and_day_of_week"
    t.index ["user_id"], name: "index_staff_availabilities_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "google_calendar_id"
    t.text "google_oauth_token"
    t.text "google_refresh_token"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "name"
    t.string "phone"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "staff", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "bookings", "accounts"
  add_foreign_key "bookings", "customers"
  add_foreign_key "bookings", "recurrence_rules"
  add_foreign_key "bookings", "services"
  add_foreign_key "bookings", "users"
  add_foreign_key "customers", "accounts"
  add_foreign_key "message_logs", "accounts"
  add_foreign_key "message_logs", "bookings"
  add_foreign_key "message_logs", "customers"
  add_foreign_key "recurrence_rules", "accounts"
  add_foreign_key "reminder_schedules", "accounts"
  add_foreign_key "reminder_schedules", "bookings"
  add_foreign_key "services", "accounts"
  add_foreign_key "staff_availabilities", "accounts"
  add_foreign_key "staff_availabilities", "users"
  add_foreign_key "users", "accounts"
end
