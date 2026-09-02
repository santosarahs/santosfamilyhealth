# Setup — deploy the live app

The app is a single static page (`index.html`). All the real work — the
database, email sign-in, file storage, and access rules — lives in a free
**Supabase** project. **Vercel** just serves the page.

Plan for ~20 minutes the first time.

---

## 1. Create the Supabase project

1. Sign up at <https://supabase.com> → **New project**.
2. Pick a name, a strong database password (save it), and the region
   closest to your family.
3. Wait for it to finish provisioning.

## 2. Create the tables and rules

1. In the project, open **SQL Editor** → **New query**.
2. Paste the entire contents of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**.
   This creates the `members`, `people`, `events` tables, the `attachments`
   storage bucket, and all row-level-security policies.

## 3. Make yourself the admin

Still in the SQL Editor, run this **on its own** — use the exact email
address you will sign in with:

```sql
insert into public.members (email, role) values ('you@example.com', 'admin');
```

Without this row, nobody can get past the sign-in screen.

## 4. Get your API keys

**Project Settings → API**. Copy two things:

| Field | Goes into |
|---|---|
| **Project URL** (`https://xxxx.supabase.co`) | `SUPABASE_URL` |
| **Project API keys → `anon` `public`** | `SUPABASE_ANON_KEY` |

The `anon` key is meant to be public — access is enforced by the security
policies and the members list, not by hiding the key.

Put them in the app one of two ways:

- **Permanent:** edit the two lines near the top of `index.html`, commit, push.
- **Quick test:** open the deployed site and paste them into the setup
  screen (stored in that browser only).

## 5. Turn on email sending (required to invite others)

Supabase's built-in email only delivers to your own project members and is
rate-limited, so for real family invites you need your own sender.

1. Create a free **[Resend](https://resend.com)** account and verify a
   sending domain (or use their onboarding sandbox for testing).
2. Resend → **API Keys** and **SMTP** settings give you host / port / user /
   password.
3. Supabase → **Authentication → Emails → SMTP Settings** → enable custom
   SMTP and paste those values. Set the sender to an address on your
   verified domain.
4. Supabase → **Authentication → Providers → Email** — make sure it's
   enabled. "Confirm email" can stay on; magic links work either way.

## 6. Set the redirect URLs

Supabase → **Authentication → URL Configuration**:

- **Site URL:** your Vercel URL, e.g. `https://santosfamilyhealth.vercel.app`
- **Redirect URLs:** add `https://santosfamilyhealth.vercel.app/**`
  (and `http://localhost:5173/**` or similar if you test locally).

Sign-in links are rejected if the return URL isn't listed here.

## 7. Deploy on Vercel

1. Sign in at <https://vercel.com> with GitHub.
2. **Add New… → Project** → import **`santosarahs/santosfamilyhealth`**.
3. Framework preset: **Other**. No build command, no output directory —
   it's a static file. Click **Deploy**.
4. Every `git push` to `main` redeploys automatically.

If you set the keys via the setup screen rather than in `index.html`,
open the deployed URL now and paste them in.

## 8. Invite your family

Sign in as the admin → **Members** (top right) → add each person's email
and role. Then tell them to open the site and request a sign-in link with
that same address. Remove anyone from the same screen.

---

## Optional — instant sync across devices

Uncomment the two `alter publication supabase_realtime …` lines at the
bottom of `schema.sql` and run them. Open browsers then update the moment
someone saves. Without it, the app still refreshes when you switch back to
the tab and after every change you make.

## Costs

Supabase free tier (500 MB database, 1 GB file storage, 50k monthly active
users) and Vercel's Hobby tier cover a family easily. Resend's free tier is
100 emails/day. None of these require a card for the free tiers.

## Notes

- All signed-in members can see and edit every person's records — it's a
  shared family ledger. Only admins can manage the members list.
- Attachments up to 25 MB each go to Supabase Storage (private; served via
  short-lived signed URLs). You can also log a "reference" — just a note of
  where a paper/portal document is kept.
- **Backup** (top right) downloads a full JSON export. Do it periodically.
- This is a personal record-keeping tool, not a medical device.
