import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "stepIndicator", "nextBtn1", "summaryService", "summaryTime", "form"]
  static values = {
    currentStep: { type: Number, default: 1 },
    selectedServiceName: { type: String, default: "" }
  }

  serviceSelected(event) {
    const label = event.target.closest("label")
    const name  = label?.querySelector("p.font-semibold")?.textContent?.trim()
    if (name) this.selectedServiceNameValue = name
    if (this.hasNextBtn1Target) {
      this.nextBtn1Target.disabled = false
    }
  }

  nextStep() {
    if (this.currentStepValue < 3) {
      this.showStep(this.currentStepValue + 1)
    }
  }

  prevStep() {
    if (this.currentStepValue > 1) {
      this.showStep(this.currentStepValue - 1)
    }
  }

  showStep(step) {
    this.currentStepValue = step

    this.stepTargets.forEach(el => {
      const idx = parseInt(el.dataset.stepIndex)
      el.classList.toggle("hidden", idx !== step)
    })

    this.stepIndicatorTargets.forEach(el => {
      const idx = parseInt(el.dataset.step)
      const circle = el.querySelector(".w-6")
      const label  = el.querySelector("span:last-child")
      if (circle) {
        circle.classList.toggle("bg-forest", idx <= step)
        circle.classList.toggle("text-cream", idx <= step)
        circle.classList.toggle("bg-cream-dark", idx > step)
        circle.classList.toggle("text-forest\\/40", idx > step)
      }
      if (label) {
        label.classList.toggle("text-forest", idx <= step)
        label.classList.toggle("text-forest\\/40", idx > step)
      }
    })

    if (step === 3) {
      this.updateSummary()
    }

    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  updateSummary() {
    if (this.hasSummaryServiceTarget && this.selectedServiceNameValue) {
      this.summaryServiceTarget.textContent = this.selectedServiceNameValue
    }

    const dateInput = this.formTarget?.querySelector("input[type='datetime-local']")
    if (this.hasSummaryTimeTarget && dateInput?.value) {
      const d = new Date(dateInput.value)
      const opts = { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }
      this.summaryTimeTarget.textContent = d.toLocaleDateString("es-MX", opts)
    }
  }
}
