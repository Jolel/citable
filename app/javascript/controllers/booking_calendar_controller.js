import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "toast"]
  static values = {
    updateUrlTemplate: String
  }

  connect() {
    this.draggedCard = null
    this.draggedBookingId = null
    this.justDragged = false
  }

  startDrag(event) {
    this.draggedCard = event.currentTarget
    this.draggedBookingId = event.currentTarget.dataset.bookingId
    this.justDragged = false

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedBookingId)

    requestAnimationFrame(() => {
      event.currentTarget.classList.add("opacity-60")
    })
  }

  endDrag(event) {
    event.currentTarget.classList.remove("opacity-60")
  }

  allowDrop(event) {
    event.preventDefault()
  }

  dropOnSlot(event) {
    event.preventDefault()

    const bookingId = event.dataTransfer.getData("text/plain")
    if (!bookingId) return

    const slot = event.currentTarget

    this.persistMove(bookingId, {
      starts_at: slot.dataset.slotStartAt,
      user_id: slot.dataset.slotUserId
    })
  }

  openBooking(event) {
    if (this.justDragged) {
      event.preventDefault()
      this.justDragged = false
      return
    }

    const url = event.currentTarget.dataset.bookingUrl
    if (url) Turbo.visit(url)
  }

  persistMove(bookingId, payload) {
    fetch(this.updateUrlTemplateValue.replace("__BOOKING_ID__", bookingId), {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({ booking: payload })
    })
      .then(async (response) => {
        if (!response.ok) {
          const data = await response.json().catch(() => ({}))
          throw new Error(data.error || "No pudimos mover la cita.")
        }

        return response.json()
      })
      .then((data) => {
        this.justDragged = true
        this.applyBookingUpdate(data.booking)
        this.showToast(data.warning_message || data.notice, Boolean(data.warning_message))
      })
      .catch((error) => {
        this.showToast(error.message, true)
      })
  }

  applyBookingUpdate(booking) {
    const card = this.element.querySelector(`[data-booking-id="${booking.id}"]`)
    const column = this.findColumn(booking.user_id, booking.day_key)
    if (!card || !column) return

    column.appendChild(card)
    card.style.top = `${booking.top_offset}px`
    card.style.height = `${booking.height}px`
    card.dataset.bookingUrl = booking.detail_url

    const timeNode = card.querySelector("p")
    if (timeNode) timeNode.textContent = booking.starts_at_label

    const infoNodes = card.querySelectorAll("p")
    if (infoNodes[1]) infoNodes[1].textContent = booking.service_name || infoNodes[1].textContent
    if (infoNodes[2]) infoNodes[2].textContent = booking.customer_name || infoNodes[2].textContent

    card.classList.remove("border-amber-600", "bg-amber-muted/80", "ring-1", "ring-amber-200", "border-brand/20", "bg-white")
    ;["absolute", "inset-x-1", "z-10", "cursor-move", "overflow-hidden", "rounded-2xl", "border", "px-3", "py-2", "shadow-sm", "transition", "hover:shadow-md"].forEach((klass) => {
      if (!card.classList.contains(klass)) card.classList.add(klass)
    })
    booking.warning_classes.split(" ").forEach((klass) => card.classList.add(klass))

    const warningContainer = card.querySelector("[data-booking-warning-container]")
    if (warningContainer) {
      warningContainer.innerHTML = ""

      if (booking.warning_labels.length > 0) {
        warningContainer.classList.remove("hidden")
        booking.warning_labels.forEach((label) => {
          const badge = document.createElement("span")
          badge.className = "inline-flex items-center rounded-full bg-white/85 px-2 py-0.5 text-[10px] font-semibold text-amber-700"
          badge.textContent = label
          warningContainer.appendChild(badge)
        })
      } else {
        warningContainer.classList.add("hidden")
      }
    }
  }

  findColumn(userId, dayKey) {
    return this.columnTargets.find((column) =>
      column.dataset.columnUserId === String(userId) && column.dataset.columnDate === dayKey
    )
  }

  showToast(message, isWarning = false) {
    if (!this.hasToastTarget || !message) return

    this.toastTarget.textContent = message
    this.toastTarget.classList.remove("hidden", "text-amber-700", "border-amber-200", "bg-amber-50", "text-emerald-800", "border-emerald-200", "bg-emerald-50")

    if (isWarning) {
      this.toastTarget.classList.add("text-amber-700", "border-amber-200", "bg-amber-50")
    } else {
      this.toastTarget.classList.add("text-emerald-800", "border-emerald-200", "bg-emerald-50")
    }

    clearTimeout(this.toastTimeout)
    this.toastTimeout = setTimeout(() => {
      this.toastTarget.classList.add("hidden")
    }, 4000)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
