# frozen_string_literal: true

# Session cookie hardening — Secure flag in production, SameSite=Lax against
# CSRF-via-third-party-page, HttpOnly so JS cannot read the cookie. The
# Secure flag in production is also enforced indirectly by force_ssl, but
# setting it explicitly here is defense-in-depth.
Rails.application.config.session_store :cookie_store,
                                       key:       "_citable_session",
                                       secure:    Rails.env.production?,
                                       same_site: :lax,
                                       httponly:  true
