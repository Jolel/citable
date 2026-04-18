module ApplicationHelper
  def dashboard_nav_link(label, path, ctrl_name)
    active = controller_name == ctrl_name
    link_to path,
      class: [
        "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
        active ? "bg-white/10 text-cream" : "text-cream/60 hover:text-cream hover:bg-white/5"
      ].join(" ") do
      content_tag(:span, active ? "●" : "○",
        class: "text-[8px] #{active ? 'text-brand-light' : 'text-cream/30'} shrink-0") +
      content_tag(:span, label)
    end
  end

  def booking_status_badge(status)
    labels = {
      "pending"   => [ "Por confirmar", "badge-pending" ],
      "confirmed" => [ "Confirmada",    "badge-confirmed" ],
      "completed" => [ "Completada",    "badge-completed" ],
      "cancelled" => [ "Cancelada",     "badge-cancelled" ],
      "no_show"   => [ "No se presentó", "badge-no-show" ]
    }
    text, css = labels[status.to_s] || [ status.to_s.humanize, "badge-pending" ]
    content_tag(:span, text, class: css)
  end

  def whatsapp_link(phone, message: nil)
    number = phone.to_s.gsub(/\D/, "")
    number = "52#{number}" unless number.start_with?("52")
    url = "https://wa.me/#{number}"
    url += "?text=#{CGI.escape(message)}" if message.present?
    url
  end
end
