# Project Brief: Citable

## One-liner
Spanish-first, WhatsApp-native appointment booking and light CRM for Mexican local-service businesses.

## Problem
Mexican solo operators (plomeros, estilistas, paseadores de perros, tutores, técnicos) run their bookings via WhatsApp + Google Sheets + paper notebook. Calendly is English-first and has no WhatsApp integration. Jobber/Housecall Pro are USD $50+/mo. AgendaPro is beauty-vertical-leaning with no free tier. The real competitor is manual work.

## Solution
A SaaS app that:
- Gives each business a mobile-first public booking page (subdomain or custom domain)
- Sends WhatsApp confirmations and reminders automatically (Twilio)
- Lets clients confirm or cancel by replying "1" or "2" on WhatsApp
- Stores all customers, bookings, and notes in one place
- Works cash-first (pay on arrival), including any deposits
- Has a genuinely usable free tier

## Primary Persona
"Ana, la estilista de la colonia" — 1-chair salon, 30-80 clients, WhatsApp-native, Spanish-only, MXN 15k-40k/mo revenue.

## Core Scope (MVP)
- Public booking page per business
- Multiple services (duration, price, optional deposit, optional address)
- Customer records with booking history, notes, custom fields, tags
- Recurring appointments (weekly, biweekly, monthly)
- Multi-staff calendars + per-staff availability
- WhatsApp confirmations + 24h/2h reminders
- Email fallback when WhatsApp quota exhausted
- Cash deposits, tracked without an online payment provider
- Google Calendar two-way sync (per staff)
- Free + Pro tiers

## Non-Goals (v1)
CFDI invoicing, dispatch/routing, native apps, English UI, MercadoPago, SMS fallback, bulk broadcasts.

## Success Criteria
- 20 pilot accounts in Mexico within 30 days of launch
- End-to-end booking → WhatsApp confirmation → reminder works with no manual steps
- Free → Pro conversion >= 8% within 60 days
- P95 booking page load < 2s on 4G Mexico
- Zero cross-tenant data leaks in first 90 days
