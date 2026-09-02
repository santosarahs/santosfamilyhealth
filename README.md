# Santos Family Health Ledger

A private web app for keeping the medical history of every member of the family in one
place — consultations, laboratory results, prescriptions, emergency visits, vitals,
immunisations and upcoming appointments — with a per‑person profile (conditions,
allergies, blood type, care team) and a filterable timeline.

Built for tracking a chronic course of care (e.g. TB treatment alongside diabetes), and
reusable for any number of family members.

## How it runs

`index.html` is a single self‑contained page. It is deployed as a **Claude Artifact**,
where it is granted two runtime capabilities:

- **`db`** – a private, per‑artifact database that stores every record. It survives
  reloads and syncs across devices.
- **`downloads`** – lets you export a full JSON backup, or one person's records as CSV.

### Access / security

Access is handled entirely by Claude, not by this code:

- The artifact uses a private database, so it **can never be shared on the public web**.
- Everyone who opens it must be **signed in to a Claude account you have shared it with**
  (via the artifact's Share menu — *Can view* = read‑only, *Can edit* = can add records).
- Leaving it unshared keeps it visible to the owner account only.

There is no separate login screen in the page: an artifact has no server and cannot send
email, so a client‑side password check would be security theatre. Claude's sign‑in is the
real gate.

### Running the file outside Claude

Opening `index.html` directly in a browser (or via GitHub Pages) works, but with no
`db`/`downloads` runtime it stays in **preview mode**: it shows built‑in example data
(a father on TB treatment with diabetes, plus a second family member) and does not save.
Use it that way only to review the interface.

## Record types

Appointment · Consultation · Laboratory (per‑analyte results with reference ranges and
normal/high/low/critical flags) · Prescription · Emergency · Vitals & readings
(blood glucose, blood pressure, weight — with a glucose trend sparkline) ·
Immunisation · History / note.

## Attachments

Each record can hold a small attached file (images are auto‑compressed; ~0.23 MB per
file) or a **reference** — the document's name plus where the physical or portal copy is
kept — for hospital paperwork that is too large or paper‑only.

## Dashboard

Next appointment, latest HbA1c vs. target, blood‑glucose trend, active‑medication count,
a **Needs attention** list (past appointments not closed out, immunisations due, follow‑up
dates passed) and an **Upcoming** section.

## Data

No real patient data is stored in this repository. The only medical content in
`index.html` is fictional example data used for the preview. Real records live in the
Claude Artifact's private database.
