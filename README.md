# Santos Family Health Ledger

A private web app for keeping the medical history of every member of the
family in one place — consultations, laboratory results, prescriptions,
emergency visits, vitals, immunisations and upcoming appointments — with a
per‑person profile (conditions, allergies, blood type, care team) and a
filterable timeline.

Built for tracking a chronic course of care (e.g. TB treatment alongside
diabetes) and reusable for any number of family members.

## Architecture

A single static page (`index.html`) hosted on **Vercel**, backed by a free
**Supabase** project:

| Concern | Handled by |
|---|---|
| Sign‑in | Supabase Auth — passwordless **email magic links** |
| Who's allowed in | a `members` table; the admin invites/removes people from inside the app |
| Data | Supabase Postgres (`people`, `events`), protected by row‑level security |
| Attachments | Supabase Storage (private bucket, 25 MB/file, signed URLs) |
| Hosting | Vercel static deploy from this repo — every push redeploys |

There is no custom backend code. `index.html` talks to Supabase directly;
the security policies in [`supabase/schema.sql`](supabase/schema.sql) are
what enforce access.

## Deploy it

See **[SETUP.md](SETUP.md)** for the full walkthrough. In short:

1. Create a Supabase project, run `supabase/schema.sql` in its SQL editor.
2. Insert your own email as the first `admin`.
3. Put the project URL + anon key into `index.html` (or the setup screen).
4. Add custom SMTP (Resend) so invite emails can reach non‑project addresses.
5. Set the Auth redirect URLs to your Vercel domain.
6. Import the repo on Vercel and deploy.

## Access model

Three roles in the `members` table, all enforced by row‑level security
(not just hidden in the UI):

| Role | View | Add / edit records & attachments | Delete records / profiles | Manage members |
|---|---|---|---|---|
| **admin** | ✅ | ✅ | ✅ | ✅ |
| **member** | ✅ | ✅ | — | — |
| **viewer** | ✅ (incl. print / CSV export) | — | — | — |

Anyone whose email isn't in `members` is stopped at the sign‑in screen.
Admins set each person's role from the **Members** dialog.

**Idle timeout:** a session is signed out after 5 minutes with no mouse,
key, touch or scroll activity, with a 60‑second "Stay signed in" warning
first. Change `IDLE_MIN` / `IDLE_WARN_SEC` near the top of `index.html`.
For defence in depth you can also set an inactivity timeout server‑side in
Supabase → Authentication → Sessions.

### Audit log

Postgres triggers record every sign‑in and every create / edit / delete on
family members, records and the member list — into an `audit_log` table,
with the acting user's email taken from their auth token server‑side (not
supplied by the browser, so it can't be forged). Admins read it in‑app via
the **Activity** button.

## Record types

Appointment · Consultation · Laboratory (per‑analyte results with reference
ranges and normal/high/low/critical flags) · Prescription · Emergency ·
Vitals & readings (blood glucose, blood pressure, weight — with a glucose
trend sparkline) · Immunisation · History / note.

## Dashboard

Next appointment, latest HbA1c vs. target, blood‑glucose trend,
active‑medication count, a **Needs attention** list (past appointments not
closed out, immunisations due, follow‑up dates passed) and an **Upcoming**
section.

## Backup

The **Backup** button downloads a full JSON export of every person and
record. Attachment files stay in Supabase Storage; the export lists their
paths.

## Data

No real patient data is stored in this repository. `index.html` ships with
**no** example data — it starts empty and is filled in through the running
app. Real records live in your Supabase project.

This is a personal record‑keeping tool, not a medical device.
