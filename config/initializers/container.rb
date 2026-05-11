# frozen_string_literal: true

# Force-load the container on every code reload so adapter registrations
# are available before the first request in production (eager-loaded) and
# survive Zeitwerk reloads in development.
Rails.application.config.to_prepare { Citable::Container }
