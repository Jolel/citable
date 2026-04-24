# frozen_string_literal: true

class Dashboard::BookingCalendarController < Dashboard::BaseController
  before_action :set_calendar_context, only: :show
  before_action :set_calendar_metrics, only: :update_event

  SLOT_MINUTES = 30
  SLOT_HEIGHT = 48

  COLLABORATOR_PALETTE = [
    { background: "#EEF7F5", border: "#7BB7AE", accent: "#128C7E" },
    { background: "#FDF3EF", border: "#E8836A", accent: "#C4522A" },
    { background: "#FDF6E3", border: "#E8A838", accent: "#B7791F" },
    { background: "#EFF6FF", border: "#93C5FD", accent: "#2563EB" },
    { background: "#F5F3FF", border: "#C4B5FD", accent: "#7C3AED" },
    { background: "#ECFDF5", border: "#86EFAC", accent: "#16A34A" }
  ].freeze

  helper_method :calendar_days, :calendar_staff, :calendar_slots, :bookings_for,
                :calendar_view_mode, :calendar_date, :calendar_prev_date,
                :calendar_next_date, :calendar_warning_labels,
                :calendar_warning_classes, :warnings_for, :slot_height, :slot_minutes,
                :calendar_period_label, :bookings_for_day, :month_day_in_focus?,
                :calendar_collaborator_style, :calendar_collaborator_dot_style,
                :timed_layout_from_bookings, :calendar_card_timed_style

  def show
    load_bookings
  end

  def update_event
    booking = current_account.bookings.includes(:service, :customer, :user).find(params[:id])
    starts_at = Time.zone.parse(calendar_booking_params[:starts_at])
    user = current_account.users.find(calendar_booking_params[:user_id])

    result = Bookings::RescheduleFromCalendar.call(booking:, starts_at:, user:)

    if result.success?
      payload = result.value!

      render json: {
        booking: booking_payload(payload[:booking], payload[:warnings]),
        notice: "Cita movida correctamente.",
        warning_message: warning_message_for(payload[:booking], payload[:warnings])
      }
    else
      render json: { error: "No pudimos mover la cita." }, status: :unprocessable_entity
    end
  rescue ArgumentError, TypeError
    render json: { error: "La fecha enviada no es válida." }, status: :unprocessable_entity
  end

  private

  def set_calendar_context
    @calendar_view_mode = %w[day week month].include?(params[:view]) ? params[:view] : "week"
    @calendar_date = parse_date(params[:date]) || Time.zone.today
    @calendar_days = build_days(@calendar_date, @calendar_view_mode)
    @calendar_staff = current_account.users.order(:name)
    set_calendar_metrics
    @calendar_slots = build_slots
  end

  def set_calendar_metrics
    @slot_minutes = SLOT_MINUTES
    @slot_height = SLOT_HEIGHT
    @start_hour = 7
    @end_hour = 21
  end

  def load_bookings
    @bookings = current_account.bookings.includes(:customer, :service, :user)
                       .where(starts_at: range_start...range_end)
                       .order(:starts_at)

    @bookings_by_day_and_user = @bookings.group_by { |booking| [ booking.starts_at.to_date, booking.user_id ] }
    @warnings_by_booking_id = compute_booking_warnings
  end

  def compute_booking_warnings
    wdays = calendar_days.map(&:wday).uniq
    user_ids = @bookings.map(&:user_id).compact.uniq

    availabilities = user_ids.any? ? StaffAvailability.active
                                                       .where(user_id: user_ids, day_of_week: wdays)
                                                       .index_by { |a| [ a.user_id, a.day_of_week ] } : {}

    active_bookings_by_user = @bookings.select { |b| %w[pending confirmed].include?(b.status) }
                                       .group_by(&:user_id)

    @bookings.to_h do |booking|
      availability = availabilities[[ booking.user_id, booking.starts_at.wday ]]
      warnings = []
      warnings << :outside_availability if outside_availability_in_memory?(booking, availability)
      warnings << :overlap if overlap_in_memory?(booking, active_bookings_by_user[booking.user_id] || [])
      [ booking.id, warnings ]
    end
  end

  def outside_availability_in_memory?(booking, availability)
    return true unless availability

    day_start = booking.starts_at.in_time_zone.beginning_of_day
    starts_seconds = (booking.starts_at - day_start).to_i
    ends_seconds = (booking.ends_at - day_start).to_i

    starts_seconds < seconds_since_midnight(availability.start_time) ||
      ends_seconds > seconds_since_midnight(availability.end_time)
  end

  def overlap_in_memory?(booking, user_bookings)
    user_bookings.any? do |other|
      other.id != booking.id &&
        other.starts_at < booking.ends_at &&
        other.ends_at > booking.starts_at
    end
  end

  def seconds_since_midnight(value)
    (value.hour * 3600) + (value.min * 60) + value.sec
  end

  def calendar_booking_params
    params.require(:booking).permit(:starts_at, :user_id)
  end

  def parse_date(value)
    return if value.blank?

    Date.parse(value)
  rescue Date::Error
    nil
  end

  def build_days(date, view_mode)
    return [ date ] if view_mode == "day"
    return month_days(date) if view_mode == "month"

    start_of_week = date.beginning_of_week(:monday)
    (start_of_week..(start_of_week + 6.days)).to_a
  end

  def month_days(date)
    first_day = date.beginning_of_month.beginning_of_week(:monday)
    last_day = date.end_of_month.end_of_week(:monday)

    (first_day..last_day).to_a
  end

  def build_slots
    current = Time.zone.local(2000, 1, 1, @start_hour, 0)
    ending = Time.zone.local(2000, 1, 1, @end_hour, 0)
    slots = []

    while current < ending
      slots << current
      current += @slot_minutes.minutes
    end

    slots
  end

  def range_start
    calendar_days.first.in_time_zone.beginning_of_day
  end

  def range_end
    (calendar_days.last + 1.day).in_time_zone.beginning_of_day
  end

  def booking_payload(booking, warnings = nil)
    warnings ||= @warnings_by_booking_id&.fetch(booking.id, [])

    {
      id: booking.id,
      user_id: booking.user_id,
      starts_at: booking.starts_at.iso8601,
      ends_at: booking.ends_at.iso8601,
      starts_at_label: booking.starts_at.strftime("%H:%M"),
      ends_at_label: booking.ends_at.strftime("%H:%M"),
      service_name: booking.service&.name,
      customer_name: booking.customer&.name,
      day_key: booking.starts_at.to_date.iso8601,
      top_offset: minutes_from_calendar_start(booking.starts_at) * @slot_height / @slot_minutes,
      height: [ ((booking.ends_at - booking.starts_at) / 60.0) * @slot_height / @slot_minutes, @slot_height ].max.round,
      warnings: warnings.map(&:to_s),
      warning_labels: calendar_warning_labels(warnings),
      warning_classes: calendar_warning_classes(warnings),
      detail_url: dashboard_booking_path(booking)
    }
  end

  def minutes_from_calendar_start(time)
    (time.hour * 60 + time.min) - (@start_hour * 60)
  end

  def warning_message_for(booking, warnings)
    return if warnings.blank?

    messages = warnings.map do |warning|
      case warning.to_sym
      when :outside_availability
        "La cita quedó fuera del horario laboral de #{booking.user.display_name}."
      when :overlap
        "La cita se empalma con otra cita de #{booking.user.display_name}."
      end
    end.compact

    messages.join(" ")
  end

  def calendar_days = @calendar_days
  def calendar_staff = @calendar_staff
  def calendar_slots = @calendar_slots
  def calendar_view_mode = @calendar_view_mode
  def calendar_date = @calendar_date
  def slot_height = @slot_height
  def slot_minutes = @slot_minutes

  def calendar_prev_date
    case calendar_view_mode
    when "day" then calendar_date - 1.day
    when "month" then calendar_date.prev_month
    else calendar_date - 1.week
    end
  end

  def calendar_next_date
    case calendar_view_mode
    when "day" then calendar_date + 1.day
    when "month" then calendar_date.next_month
    else calendar_date + 1.week
    end
  end

  def calendar_period_label
    case calendar_view_mode
    when "day"
      I18n.l(calendar_date, format: "%A %d de %B").capitalize
    when "month"
      I18n.l(calendar_date, format: "%B %Y").capitalize
    else
      "#{I18n.l(calendar_days.first, format: "%d %b").capitalize} - #{I18n.l(calendar_days.last, format: "%d %b").capitalize}"
    end
  end

  def bookings_for(day, user)
    @bookings_by_day_and_user.fetch([ day, user.id ], [])
  end

  def bookings_for_day(day)
    calendar_staff.flat_map { |user| bookings_for(day, user) }.sort_by(&:starts_at)
  end

  def month_day_in_focus?(day)
    day.month == calendar_date.month
  end

  def warnings_for(booking)
    @warnings_by_booking_id.fetch(booking.id, [])
  end

  def timed_layout_from_bookings(bookings)
    return {} if bookings.empty?

    sorted = bookings.sort_by { |b| [ b.starts_at, b.ends_at ] }
    col_ends = []
    placement = {}

    sorted.each do |booking|
      col = col_ends.index { |t| t <= booking.starts_at } || col_ends.size
      col_ends[col] = booking.ends_at
      placement[booking.id] = col
    end

    sorted.each_with_object({}) do |booking, result|
      concurrent = sorted.select { |o| o.starts_at < booking.ends_at && o.ends_at > booking.starts_at }
      total = concurrent.map { |b| placement[b.id] }.max + 1
      result[booking.id] = { col: placement[booking.id], total: }
    end
  end

  def calendar_card_timed_style(booking, layout)
    top = minutes_from_calendar_start(booking.starts_at) * @slot_height / @slot_minutes
    height = [ ((booking.ends_at - booking.starts_at) / 60.0) * @slot_height / @slot_minutes, @slot_height ].max.round
    info = layout[booking.id] || { col: 0, total: 1 }
    width_pct = (100.0 / info[:total]).round(4)
    left_pct = (info[:col] * width_pct).round(4)
    "top: #{top}px; height: #{height}px; left: calc(#{left_pct}% + 4px); width: calc(#{width_pct}% - 8px);"
  end

  def calendar_collaborator_style(user)
    colors = collaborator_colors(user)
    "background-color: #{colors[:background]}; border-color: #{colors[:border]};"
  end

  def calendar_collaborator_dot_style(user)
    "background-color: #{collaborator_colors(user)[:accent]};"
  end

  def collaborator_colors(user)
    COLLABORATOR_PALETTE[user.id % COLLABORATOR_PALETTE.size]
  end

  def calendar_warning_labels(warnings)
    Array(warnings).map do |warning|
      case warning.to_sym
      when :outside_availability then "Fuera de horario"
      when :overlap then "Empalmada"
      end
    end.compact
  end

  def calendar_warning_classes(warnings)
    return "border-brand/20 bg-white" if Array(warnings).blank?

    "border-amber-600 bg-amber-muted/80 ring-1 ring-amber-200"
  end
end
