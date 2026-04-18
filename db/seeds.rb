puts "Seeding development data..."

ActsAsTenant.without_tenant do
  # Create a sample account (the "Ana" persona from the design doc)
  account = Account.find_or_create_by!(subdomain: "ana") do |a|
    a.name     = "Estudio de Ana"
    a.timezone = "America/Mexico_City"
    a.locale   = "es-MX"
    a.plan     = "free"
  end
  puts "Account: #{account.name} (subdomain: #{account.subdomain})"

  # Owner user
  owner = User.find_or_create_by!(email: "ana@example.com") do |u|
    u.account  = account
    u.name     = "Ana López"
    u.phone    = "+5215512345678"
    u.role     = :owner
    u.password = "password123"
    u.password_confirmation = "password123"
  end
  puts "Owner: #{owner.email} / password: password123"

  # Staff member
  staff = User.find_or_create_by!(email: "maria@example.com") do |u|
    u.account  = account
    u.name     = "María Jiménez"
    u.phone    = "+5215587654321"
    u.role     = :staff
    u.password = "password123"
    u.password_confirmation = "password123"
  end
  puts "Staff: #{staff.email}"

  ActsAsTenant.with_tenant(account) do
    # Services
    corte = Service.find_or_create_by!(name: "Corte de cabello") do |s|
      s.duration_minutes    = 45
      s.price_cents         = 25000
      s.requires_address    = false
      s.deposit_amount_cents = 0
    end

    tinte = Service.find_or_create_by!(name: "Tinte y highlights") do |s|
      s.duration_minutes    = 120
      s.price_cents         = 85000
      s.requires_address    = false
      s.deposit_amount_cents = 20000
    end

    peinado = Service.find_or_create_by!(name: "Peinado especial") do |s|
      s.duration_minutes    = 60
      s.price_cents         = 45000
      s.requires_address    = false
      s.deposit_amount_cents = 0
    end
    puts "Services: #{[ corte, tinte, peinado ].map(&:name).join(', ')}"

    # Staff availability (Mon-Sat, 9am-6pm)
    (1..6).each do |day|
      StaffAvailability.find_or_create_by!(user: owner, day_of_week: day) do |sa|
        sa.start_time = "09:00"
        sa.end_time   = "18:00"
        sa.active     = true
      end
      StaffAvailability.find_or_create_by!(user: staff, day_of_week: day) do |sa|
        sa.start_time = "10:00"
        sa.end_time   = "17:00"
        sa.active     = true
      end
    end
    puts "Staff availabilities created"

    # Sample customers
    rosa = Customer.find_or_create_by!(phone: "+5215511111111") do |c|
      c.name  = "Rosa Martínez"
      c.notes = "Prefiere citas por la mañana"
      c.tags  = [ "vip", "frecuente" ]
    end

    carlos = Customer.find_or_create_by!(phone: "+5215522222222") do |c|
      c.name = "Carlos Hernández"
    end
    puts "Customers: #{[ rosa, carlos ].map(&:name).join(', ')}"

    # Sample booking (tomorrow at 10am)
    tomorrow_10am = Time.current.beginning_of_day + 1.day + 10.hours
    booking = Booking.find_or_create_by!(customer: rosa, service: corte, starts_at: tomorrow_10am) do |b|
      b.user    = owner
      b.status  = :pending
    end
    puts "Booking: #{rosa.name} - #{corte.name} at #{booking.starts_at}"
  end
end

puts "Done! Visit http://ana.citable.localhost:3000 or use subdomain 'ana'"
