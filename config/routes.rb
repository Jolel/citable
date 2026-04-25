Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise auth (scoped to dashboard)
  devise_for :users, path: "dashboard/auth",
             path_names: { sign_in: "entrar", sign_out: "salir", sign_up: "registrarse" }

  # Owner / staff dashboard
  namespace :dashboard do
    root "bookings#index"

    resource :calendar, only: :show, controller: "booking_calendar" do
      patch "events/:id", action: :update_event, as: :event, on: :collection
    end

    resources :bookings do
      member do
        patch :confirm
        patch :cancel
      end
    end

    resources :customers
    resources :services, except: :destroy do
      member do
        patch :toggle_active
        patch :deactivate
      end
    end

    resources :staff, only: %i[index show new create edit update destroy]

    resource :settings, only: %i[show update]

    resource :google_calendar, only: [], controller: "google_calendar" do
      delete :disconnect, on: :member
    end

    resource :google_oauth, only: [], controller: "google_oauth" do
      get    :connect
      get    :callback
      delete :disconnect
    end
  end

  # Inbound webhooks (no auth, no CSRF)
  namespace :webhooks do
    post "twilio",          to: "twilio#create",          as: :twilio
    post "google_calendar", to: "google_calendar#create", as: :google_calendar
  end

  # Public booking pages (account resolved from :slug in path)
  scope module: :public do
    get  "/reservar/:slug",                  to: "bookings#new",          as: :public_booking
    post "/reservar/:slug",                  to: "bookings#create"
    get  "/reservar/:slug/confirmada/:id",   to: "bookings#confirmation", as: :public_booking_confirmation
  end

  # Default root
  root "dashboard/bookings#index"
end
