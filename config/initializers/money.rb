MoneyRails.configure do |config|
  config.default_currency = :mxn

  config.locale_backend = :i18n

  config.rounding_mode = BigDecimal::ROUND_HALF_UP
end
