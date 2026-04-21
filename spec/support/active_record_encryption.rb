# Provide deterministic encryption keys for test environment so that
# models using `encrypts :field` (e.g. User#google_oauth_token) work
# without requiring real credentials.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Encryption.configure(
    primary_key:       "t" * 32,
    deterministic_key: "t" * 32,
    key_derivation_salt: "t" * 32
  )
end
