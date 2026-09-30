# <Module Name> — Frontend Tasks

**Module:** `NN-<module-name>`
**Stack:** Next.js App Router · TypeScript strict · Tailwind v4 tokens · shadcn/ui · Motion · Embla · RHF + Zod
**Last updated:** YYYY-MM-DD

> `design-system.md` is binding: tokens only, the type scale, the motion system (§7), the review
> checklist (§12).

---

## 1. Screen Inventory

| # | Route | Screen | Rendering | Access |
| --- | --- | --- | --- | --- |
| 1 | | | Server Component (+ islands) | Public / Admin |

## 2. Screen Breakdown

### 2.1 `<Screen>` — `<route>`

**Layout**

```text
<ASCII wireframe — mobile and desktop where they differ>
```

**Components**

| Component | Server/Client | Notes |
| --- | --- | --- |
| | | |

**States**

| State | Behaviour |
| --- | --- |
| Loading | Skeleton matching the final layout |
| Empty | Public: section hidden · Admin: explanation + primary action |
| Error | Boundary with retry and request id |
| Not found | Branded 404 |
| Success | |

## 3. Forms

| Field | Control | Zod rule | Default | Conditional on |
| --- | --- | --- | --- | --- |
| | | | | |

Submission: same Zod schema on the server · disable while pending · map `fields` errors · never lose
input · unsaved-changes guard (admin).

## 4. Data Flow

| Need | Mechanism |
| --- | --- |
| Public read | Server Component → cached service read |
| Admin mutation | Server Action → toast + revalidated view |

## 5. Motion Spec

| Element | Variant / technique | Trigger | Communicates | Reduced motion |
| --- | --- | --- | --- | --- |
| | | | | |

## 6. Responsive Behaviour

| Surface | < 640 | 640–1023 | ≥ 1024 |
| --- | --- | --- | --- |
| | | | |

## 7. Accessibility

- [ ] Landmarks, one `h1`, heading order
- [ ] Keyboard path complete; focus visible and never lost
- [ ] Labels, descriptions, error announcements
- [ ] Contrast in both themes
- [ ] Motion: reduced-motion variant verified

## 8. Design-System Compliance

`design-system.md` §13 checklist passes.

## 9. Task Checklist

- [ ] `<PREFIX>-FE-001`
