# HPB-AI: authority (permission) audit, 2026-10-07

Read-only audit of how roles and authorities are used. Nothing was changed.

## 1. The core problem

`@EnableMethodSecurity` is not switched on anywhere in `11.-HPB`. Every `@PreAuthorize("hasAuthority(...)")`
in the code is therefore **inactive**. Authorities only decide what the menu and buttons *show* in the browser.
Any logged-in user can call any API, for example with the browser console.

Proof (logged in as a user with the role Clinician, which has no Setting or Role Management authorities):

| Call | Expected | Got |
|---|---|---|
| `POST /api/freezer` | refused (no `FREEZER_C`) | 200, record created |
| `POST /api/lab-draw-role` | refused (no `LAB_DRAW_ROLE_C`) | 200, record created |
| `GET /api/role`, `GET /api/authority` | refused | 200 |

(The two test records were deleted again.)

Not enforced, so at risk today: creating, changing or deleting **roles, authorities, users and every lookup list**.

## 2. Numbers

| What | Count |
|---|---|
| Authorities checked in code (`@PreAuthorize`) | 505 |
| Authorities that exist in the database | 677 |
| Controllers | 146 (about 986 endpoints); only 21 carry any `@PreAuthorize` |
| Service classes with at least one public data method **without** `@PreAuthorize` | 125 |

## 3. What would break if enforcement were simply switched on

**3a. Checked in code but missing from the database (nobody could use them, not even Super Admin):**
`PATIENT_LOG_RA`, `MEDICAL_HISTORY_LOG_RA`, `FAMILY_HISTORY_LOG_RA`, `SAMPLE_LOG_RA`, `DIAGNOSTIC_LOG_RA`,
`STATUS_LOG_RA`, `SUB_EVENT_LOG_RA`, `LOG_E` (all the Logs pages), and `EVENT_TYPE_C/D/U`
(removed on purpose by migration V1_1_161).

**3b. Exist in the database but are held by NO role, not even Super Admin (91 authorities):**
- Newer lookups whose read authority the event forms need for their dropdowns:
  `MDK_FLOW_TYPE`, `PANEL_CONTEXT_TYPE`, `PROVENANCE_TYPE`, `PATIENT_FLOW_TYPE`, `ROUTE_TO_DIAGNOSIS_TYPE`,
  `REVIEWER_PATTERN_TYPE`, `RADIOLOGIST_ASSESSMENT_TYPE`, `RADIOLOGY_OTHER_ROLE_TYPE`,
  `ASSESSMENT_PURPOSE_TYPE`, `HISTORICAL_TUMOR_TYPE_DEFINITION`, `HISTORICAL_TUMOR_SUBTYPE_DEFINITION`
  (each with `_C`, `_D`, `_RA`, `_U`).
- The standalone endpoints of `RADIOLOGY_*`, `EVENT_PATHOLOGY_*`, `MEDICAL_ASSESSMENT_*`, `BLOOD_SAMPLE_*`,
  `SUBEVENT_BIOPSY/CYTOLOGY/RESECTION_*`, `RESECTION_MARGIN_FORM_*`, `EXTERNAL_LINK_*`, `EVENT_SUB_EVENT_C`,
  and the MDT import/export authorities.

Switching enforcement on without fixing 3a and 3b would make dropdowns and pages fail for everybody.

## 4. What enforcement would still NOT protect (no `@PreAuthorize` at all)

Examples of public service methods without any check (125 service classes in total):
- `UserServiceImpl.save` (creating a user)
- `PatientIdServiceImpl` save, update, delete
- `PreEventServiceImpl` save, update, delete; `EventSubEventServiceImpl` update, delete
- `importData` and `exportFile` of almost every lookup list
- many `getAll`, `getById` and PDF export methods

## 5. Proposed plan (nothing started)

1. **Interim fix, small and safe:** in `SecurityConfig`, require the right authority for create/change/delete on
   `/api/role`, `/api/authority` and `/api/user`. These pages are used only by Super Admin, and reading `/api/user`
   stays open to every logged-in user (the event form needs it).
2. **Data fix (one migration):** seed the missing log authorities (3a) and grant everything the code needs to Super Admin;
   then give the other roles sensible grants (Clinician script as a model).
3. **Code fix:** add `@PreAuthorize` to the unprotected write, import, export and user-creation methods (section 4).
4. **Switch on** `@EnableMethodSecurity` in a test environment.
5. **Test every page for every role** (Super Admin, Clinician, Researcher, Student, the pathologist account), and keep the
   switch easy to turn off again.
6. Only then deploy to the server.
