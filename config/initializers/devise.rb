Devise.setup do |config|
  require 'devise/orm/active_record'

  config.secret_key = Rails.application.secret_key_base
  config.mailer_sender = 'admin@lumendatabase.org'
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 10
  config.password_length = 8..128
  config.email_regexp = /\A[^@]+@[^@]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :get
  config.paranoid = true
end
