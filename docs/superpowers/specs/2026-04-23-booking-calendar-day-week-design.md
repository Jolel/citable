# Booking Calendar (Day + Week) — Design Spec
**Date:** 2026-04-23
**Status:** Pending user review

---

## Overview

Implement a calendar view inside the dashboard bookings area that feels closer to Google Calendar while staying native to the current Rails + Hotwire stack. The first version will support `Day` and `Week` views only, with drag-and-drop rescheduling and reassignment between staff columns. Changes save immediately when the booking is dropped. Conflicts and out-of-hours placements are allowed, but the UI must surface a clear warning state after the update succeeds.

This feature is intended to complement, not replace, the current bookings list. The list remains useful for scanning upcoming/past bookings; the calendar becomes the operational view for moving appointments around.

---

## Decisions Made

| Question | Decision |
|---|---|
| Implementation approach | Native Hotwire + Stimulus calendar, no large JS calendar dependency |
| Initial views | `Week` and `Day`, with `Month` added as the follow-up scanning view |
| Save behavior | Immediate save on drop |
| Staff layout | Columns by collaborator |
| Invalid placement | Allowed, but marked with a warning |
| Existing list view | Kept as an alternate tab/view |
| Month view | Out of scope for v1, but documented for future extension |

---

## Goals

- Make rescheduling much faster than editing bookings one by one.
- Let staff move bookings across time slots and collaborators directly from the calendar.
- Preserve Citable's Spanish-first dashboard feel instead of embedding a third-party calendar widget.
- Support a mobile-aware `Day` view and a desktop-first `Week` view.
- Surface operational problems without blocking workflow.

## Non-Goals

- Time selection inside the month grid
- Recurring booking drag-and-drop editing
- Drag-resizing booking duration in v1
- External calendar conflict detection against Google or other providers
- Undo history beyond standard edit flows

---

## User Experience

### Entry Point

Inside `Citas`, add a view switcher:

- `Lista`
- `Día`
- `Semana`

`Semana` is the primary operational mode on desktop. `Día` is optimized for narrower layouts and quicker single-day dispatching.

### Week View

- Horizontal columns for collaborators
- Vertical time grid, likely 30-minute rows with visible hour separators
- A top toolbar for:
  - previous / next period
  - "Hoy"
  - view toggle between `Día` and `Semana`
  - optional collaborator filter if the account has many staff members later
- Each booking appears as a positioned card containing:
  - start time
  - service name
  - customer name
  - visual status marker
  - warning icon/text if the placement is problematic

### Day View

- Reuses the same visual grammar and drag behavior
- Focuses on one date only
- Keeps collaborator separation
- Becomes the preferred mobile experience because columns remain readable

### Month View

- Shows a Monday-first month grid with leading and trailing days from adjacent months
- Each day cell shows compact booking pills ordered by start time
- Cells show up to three visible bookings, followed by `+N más` linking into `Día`
- Clicking the day number opens the `Día` view for that date
- Dragging a booking between day cells preserves its original time, duration, and collaborator
- Month View is for scanning and date-level rescheduling, not precise time placement

### Drag and Drop

- User drags a booking card vertically to change time
- User drags across columns to reassign to another collaborator
- On drop:
  - UI snaps to the nearest supported slot
  - request is sent immediately
  - optimistic movement is acceptable if the final server response is quickly reconciled
- The final saved state comes from the server response

### Warning Behavior

Dropping into a problematic slot still saves the booking. The server returns warning metadata and the client shows:

- warning styling on the booking card
- toast or inline banner indicating what happened

Initial warning types:

- overlaps another booking for that collaborator
- outside collaborator availability

### Click Behavior

- Clicking a booking without dragging opens the existing booking detail page
- If a drag just occurred, accidental navigation should be suppressed

---

## Architecture

### Controller Shape

Preferred approach: add a dedicated controller rather than making `Dashboard::BookingsController` absorb more UI modes.

```text
Dashboard::BookingCalendarController
  GET /dashboard/calendar             -> page shell
  GET /dashboard/calendar/events      -> bookings for visible range
  PATCH /dashboard/calendar/events/:id -> move/reassign booking
```

Alternative: nest this under `Dashboard::BookingsController`. The dedicated controller is cleaner because the calendar has distinct query patterns and interaction endpoints.

### View Composition

Page shell rendered by Rails:

- toolbar
- view switcher
- date header
- empty-state handling
- calendar grid container

Stimulus controller responsibilities:

- current visible range
- pointer-driven drag state
- slot snapping
- converting drop position into `starts_at`, `ends_at`, and `user_id`
- fetching/reconciling updated booking state
- rendering warning states and toasts

### Data Flow

1. User opens `Día` or `Semana`
2. Rails renders shell and initial dataset for the visible range
3. Stimulus enhances the grid and makes bookings draggable
4. User drags and drops a booking
5. Frontend submits lightweight `PATCH`
6. Server persists update and returns normalized booking payload plus warnings
7. Client updates the moved card and any affected warning markers

---

## Data and Domain Rules

### Existing Models Reused

- `Booking`
- `User`
- `StaffAvailability`

No new persistent model is required in v1.

### Proposed Service Object

Create a service that centralizes the business rules for calendar moves.

Suggested name:

```ruby
Bookings::RescheduleFromCalendar
```

Responsibilities:

- load the booking within tenant scope
- apply proposed `starts_at`, `ends_at`, and `user_id`
- persist the booking
- compute warning metadata
- return a normalized result object for the controller

This keeps controllers small and makes warning behavior testable in isolation.

### Warning Evaluation

The service should compute warnings after determining the proposed placement.

Initial rules:

1. `outside_availability`
   - the booking falls partially or completely outside the assigned collaborator's working hours for that weekday

2. `overlap`
   - the assigned collaborator already has another booking that intersects the new time range

Important: these are warnings, not validation failures, for this calendar workflow.

### Duration Handling

In v1, dragging changes start time and collaborator, but does not change duration. `ends_at` should be recalculated from the original booking duration unless explicit duration changes are introduced later.

---

## Endpoint Contract

### Fetch Events

```text
GET /dashboard/calendar/events?view=week&starts_on=2026-04-20
GET /dashboard/calendar/events?view=day&date=2026-04-23
```

Response includes:

- visible date range
- collaborators to show
- bookings in normalized calendar form

Suggested booking payload:

```json
{
  "id": 123,
  "title": "Corte de cabello",
  "customer_name": "Rosa Martínez",
  "status": "pending",
  "user_id": 8,
  "starts_at": "2026-04-23T10:00:00-06:00",
  "ends_at": "2026-04-23T11:00:00-06:00",
  "warnings": ["overlap"]
}
```

### Move Event

```text
PATCH /dashboard/calendar/events/:id
```

Request body:

```json
{
  "booking": {
    "starts_at": "2026-04-23T12:00:00-06:00",
    "user_id": 9
  }
}
```

Response body:

```json
{
  "booking": {
    "id": 123,
    "user_id": 9,
    "starts_at": "2026-04-23T12:00:00-06:00",
    "ends_at": "2026-04-23T13:00:00-06:00",
    "warnings": ["outside_availability"]
  },
  "notice": "Cita movida correctamente.",
  "warning_message": "La cita quedó fuera del horario laboral de María."
}
```

---

## UI States

### Booking Card Styles

Each card should visually encode:

- booking status
- drag state
- warning presence

Warning appearance should be hard to miss. For example:

- amber outline or striped accent
- warning icon
- short label like `Empalmada` or `Fuera de horario`

### Empty States

- No collaborators configured
- No bookings in visible range
- No availability for selected day

### Loading and Failure States

- Skeleton or subtle loading state while fetching a new range
- If save fails:
  - move card back to original slot
  - show error toast
  - keep the current calendar viewport intact

---

## Mobile and Responsive Behavior

### Day View

- first-class mobile mode
- one date visible
- collaborator columns remain, but horizontal density must stay manageable

### Week View

- desktop-first
- on smaller screens, allow horizontal scrolling for collaborator columns
- preserve sticky time gutter and sticky collaborator headers if feasible

### Drag UX

- touch dragging needs larger grab targets than desktop pointer dragging
- avoid tiny handles in v1; make the whole card draggable
- ensure tapping still opens details when the gesture was not a drag

---

## Testing Strategy

### Request Specs

- loads week range correctly within tenant scope
- loads day range correctly within tenant scope
- updates booking time and collaborator from calendar endpoint
- returns warning metadata when overlap occurs
- returns warning metadata when moved outside availability

### Service Specs

For `Bookings::RescheduleFromCalendar`:

- preserves original duration
- reassigns collaborator correctly
- detects overlap with same collaborator
- does not flag overlap against the moved booking itself
- detects outside-availability by weekday/time window
- succeeds even when warnings are present

### System Specs

- switch from list to calendar
- navigate between day and week
- drag booking to a new slot and see it move
- show warning styling after dropping into a problematic slot

Note: full drag-and-drop system coverage can be brittle. Keep the most detailed business assertions in request/service specs.

---

## Risks

### Drag Precision

Hand-rolled drag-and-drop inside a time grid is the biggest implementation risk. Slot detection, scroll offsets, touch support, and snapping must be carefully tested.

### Warning Clarity

Allowing invalid placements is a deliberate product decision. If the warning signal is weak, users may accidentally create operational issues without noticing.

### Performance

Accounts with many collaborators or dense schedules could make week rendering expensive. The event payload and DOM structure should stay lean.

### Interaction Conflicts

The same card supports both navigation and dragging. Gesture thresholds must be explicit so the user does not accidentally navigate while trying to move a booking.

---

## Month View Extension

The calendar now includes `Month` as a compact operational overview. It uses the same range querying, booking serialization, warning evaluation, and move endpoint as `Día` and `Semana`.

### Reusable Range Querying

- event fetching already works by visible date range, not by hardcoded week assumptions

### Shared Event Serialization

- booking payload shape should not be tied to a vertical-grid-only UI

### Month Requirements

- compact per-day card rendering
- `+N más` overflow handling inside cells
- drag-and-drop between day cells
- click-through from day cell to `Día`
- performance rules for rendering large date grids

---

## Recommended File Shape

```text
app/controllers/dashboard/booking_calendar_controller.rb
app/services/bookings/reschedule_from_calendar.rb
app/javascript/controllers/booking_calendar_controller.js
app/views/dashboard/booking_calendar/show.html.erb
app/views/dashboard/booking_calendar/_toolbar.html.erb
app/views/dashboard/booking_calendar/_grid.html.erb
spec/requests/dashboard/booking_calendar_spec.rb
spec/services/bookings/reschedule_from_calendar_spec.rb
spec/system/dashboard/booking_calendar_spec.rb
```

---

## Rollout Plan

1. Add calendar page shell and routing
2. Render non-interactive `Día` and `Semana` grid with real bookings
3. Add drag-and-drop with immediate save
4. Add warning evaluation and warning styling
5. Add system/request/service coverage
6. Iterate on spacing, scrolling, and mobile handling

---

## Open Assumptions Captured

- Calendar saves should happen immediately without confirmation
- `Day` and `Week` are sufficient for v1
- Staff columns matter more than a mixed single-lane view
- Warnings should not block scheduling changes
- Existing booking detail/edit flows remain in place
