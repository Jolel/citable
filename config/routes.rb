Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise auth (scoped to dashboard)
  devise_for :users, path: "dashboard/auth",
             path_names: { sign_in: "entrar", sign_out: "salir", sign_up: "registrarse" }

  # Owner / staff dashboard
  namespace :dashboard do
    root "bookings#index"

    resources :bookings do
      member do
        patch :confirm
        patch :cancel
      end
    end

    resources :customers
    resources :services do
      member do
        patch :toggle_active
      end
    end

    resources :staff, only: %i[index show new create edit update destroy]

    resource :settings, only: %i[show update]

    resource :google_oauth, only: [] do
      get    :connect
      get    :callback
      delete :disconnect
    end
  end

  # Inbound webhooks (no auth, no CSRF)
  namespace :webhooks do
    post :twilio
    post :stripe
    post :google_calendar
  end

  # Public booking pages (subdomain-based tenant resolution happens in ApplicationController)
  scope module: :public do
    get  "/reservar",            to: "bookings#new",          as: :public_booking
    post "/reservar",            to: "bookings#create"
    get  "/reservar/confirmada/:id", to: "bookings#confirmation", as: :public_booking_confirmation
  end

  # Default root
  root "dashboard/bookings#index"
end
