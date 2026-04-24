# frozen_string_literal: true

require_relative "../../lib/citable/container"

# Finalize eagerly outside test so all providers boot and components load up-front.
# In test env the container stays open so specs can substitute dependencies.
Citable::Container.finalize! unless Rails.env.test?
