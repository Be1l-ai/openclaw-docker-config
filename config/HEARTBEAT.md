# HEARTBEAT — Autonomous Scheduled Tasks

Defines tasks the agent executes automatically on a schedule, without waiting
for a user prompt.

---

## 1. Morning Assignment Digest

| Field    | Value |
|----------|-------|
| Schedule | `0 8 * * *` (every day at 08:00 UTC) |
| Scope    | `workspace/Assignments/` |

### Steps

1. **Scan** the `Assignments/` folder for files (`.md` and `.pdf`) that are
   new or modified since the last run.
2. **For `.md` assignment files** — read the structured frontmatter:
   - Extract **Title**, **Deadline**, **Status**.
   - Flag any assignment whose deadline is **today or tomorrow** as urgent.
   - Flag any assignment whose deadline has **passed** and status is not
     `✅ Done` — auto-update its status to `❌ Overdue`.
3. **For `.pdf` files** — extract text content and summarize in 3–5 bullet
   points (title, due date, key deliverables).
4. **Save** each new summary to `Assignments/summaries/<filename>-summary.md`.
5. **Post** a consolidated digest message to the active channel:
   ```
   📚 Morning Assignment Digest — <date>

   🔴 URGENT (due within 48h):
   • Binary Trees HW — due Mar 15, 23:59 — 🟡 Pending

   📋 All active:
   • OS Lab Report — due Mar 18, 17:00 — 🔵 In Progress
   • Networking Quiz Prep — due Mar 22 — 🟡 Pending

   ✅ Recently completed: 1
   ❌ Newly overdue: 0
   ```

### Conditions

- If no new/modified files and no urgent deadlines, skip silently (no message).
- If PDF text extraction fails, note the filename and "could not extract" in
  the digest.
- Always post if there are **urgent** (≤48h) deadlines, even if nothing is new.

---

## 2. Daily Tech Brief (Optional)

| Field    | Value |
|----------|-------|
| Schedule | `30 8 * * 1-5` (weekdays at 08:30 UTC) |
| Scope    | Web search |
| Requires | `BRAVE_API_KEY` set in environment |

### Steps

1. Search for the **top 3 CS / tech news** headlines from the past 24 hours.
2. For each headline: title, source, one-sentence summary, and link.
3. Save to `daily-briefs/YYYY-MM-DD.md`.
4. Post a brief summary message to the active channel.

### Conditions

- Only runs if `BRAVE_API_KEY` is configured (skip otherwise).
- Keep the brief concise — max 10 lines.
