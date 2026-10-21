# HPB-AI clean install checklist (empty database to a usable test instance)

Written 2026-10-20 from a dry run on an empty local schema: all 199 migrations (up to V1_1_179) were applied by the
application, the lookup import was run against it, then the schema was dropped. Nothing was run on the test server.
Server-specific steps (Linux account, MySQL user, Apache, Tomcat swap) stay in the Test Server Deployment Runbook.

## 0. Before you start
- Java 21 on the machine that builds (`JAVA_HOME=$(/usr/libexec/java_home -v 21)` on a Mac; a newer JDK breaks Lombok).
- MySQL with `log_bin_trust_function_creators=1`, a database created with `CHARACTER SET utf8mb4` and a user that owns it.
- `file.saving.directory` and `file.saving.directory.temp` in `application.properties` must point to folders that exist
  and are writable (the old `/opt/tomcat9/` path caused "Error saving PDF file").
- Run the patch check before building: nothing may differ between `ai_agent_learning/backend_patches` and `11.-HPB`.
- A database dump first, if the database already holds anything you want to keep.
- Deploying **without** `--keep-db` drops the whole database: patients, users, roles, lists, templates.

## 1. Create the empty database and start the application once
Use `deploy_hpb_server.sh --local-only` (no `--keep-db`) on the server, or `deploy_hpb_local.sh` on a Mac.
Flyway builds everything. What a fresh instance contains (checked):

| What | Content |
|---|---|
| Tables | 185 `tbl_*` tables, Hibernate schema validation passes |
| Authorities | 721 |
| Roles | Super Admin (721 authorities), Doctor (176), Researcher (176), Student (40) |
| Users | `sa@`, `doctor@`, `researcher@`, `student@yopmail.com`, all with the same default password (development only) |
| Patients, events | none |
| Lists filled by migrations | Age Band 16, Analysis Status 3, Assessment Purpose 3, Blood Sample Process 2, Blood Sample Tube Type 2, Discipline 6, Event Status 3, Event Type 10, Extraction Method 8, Freezer 2, Lab Draw Role 3, MDK Flow 5, Organization 4, Panel Context 5, Patient Flow 5, Provenance 3, Radiologist Assessment 6, Radiology Other Role 5, Reference Document 1, Reviewer Pattern 5, Route to Diagnosis 5, Sample Quality 3, Sample Type 2, Stent 3, Surgical Approach 3, Surgical Procedure 30, Tissue Sample Process 7, Treatment Intent 4 |
| Progression chart | 1 template, "Pancreatic cancer progression", 8 panels (the CA 19-9 panel finds its test by name, see step 3) |

## 2. Log in as Super Admin and secure the demo accounts
- Log in as `sa@yopmail.com` with the default password and change it (or create a real Super Admin and remove this one).
- The `doctor@`, `researcher@` and `student@` accounts and the demo roles come from the first version. Change their
  passwords or remove them before real use. (Login with password and BankID is planned later.)

## 3. Import the lookup lists (the first step in using the application)
From `deploy_HPB/` (needs `.env` with `HPB_ADMIN_USERNAME` and `HPB_ADMIN_PASSWORD`; use `BASE_URL=...` for a server):

```
./imports_fixed.sh import.csv
```

Dry-run result on an empty database after the fixes of 2026-10-20 (200 migrations, up to V1_1_180):
**50 lists imported, 8 already present, 0 failed.** The 8 "already present" were filled by the migrations
(analysisStatus, blood-sample-process-definition, blood-sample-tube-type-definition, extractionMethod, panelContextType,
assessmentPurposeType, lab-draw-role, freezer); the script now reports them as present, not failed. `laboratory`
(`Laboratory_export.xlsx`, Laboratory 1 to Laboratory 5) is part of the import.
Which lists exist, which are used and where each comes from: `LOOKUP_LISTS_INVENTORY.md`.
- After the import the chart template resolves CA 19-9 and its bilirubin pair by name (verified through the API).
- `update_lab_lookup_revision_2026-10-06.sql` is **not** needed on a fresh database (the workbook already has the values).
- The Grade list comes from `Grade_export.xlsx` (corrected 2026-10-20 to 1 mild ... 5 death).

## 4. Lists still empty after the import
- **Laboratory**: now imported (placeholder names Laboratory 1 to 5): rename them in the Excel file before the import, or
  in Settings afterwards.
- Lists no form uses today stay empty on purpose: Event Attribute, T/N/M and their texts, Secondary Grade of
  Differentiation, Tissue Sample NGS Panel, Tube Type, Coding System Version (see `LOOKUP_LISTS_INVENTORY.md`, section D).
  They are candidates for removal after the test phase.

## 5. Roles (run in this order, after the application has started once; see `Populate DB/ROLES_README.md`)
1. `bootstrap_roles_clinician_researcher.sql`, 2. `update_role_clinician_2026-10-07.sql`,
3. `update_role_researcher_2026-10-09.sql`, 4. `update_role_sampling_and_lookup_rules_2026-10-13.sql`.
All are idempotent. The seeded **Researcher** role already exists (176 authorities); the scripts bring it to the agreed rules.
The seeded **Doctor** role is not part of the agreed set (Clinician is): decide whether to remove Doctor and
`doctor@` (see Known issues 3). Student and lab personnel roles are waiting for the pathologist's answers.
Log in again after a role changes: rights are read at login.

## 6. Users for testers
Create them in the User page with the intended role. Bulk Import needs `BULK_IMPORT_C` plus `EVENT_C` and
`LAB_TEST_RESULT_C` (Runbook Part H).

## 7. Test data (optional, after steps 1 to 6)
- Synthetic patients: `Populate DB/synthetic_test_patients.sql`, then `synthetic_test_patients_surgery_pathology_v2.sql`.
  They reference lookup values by name, so the lookup import (step 3) must have run first.
- The scripts write `tbl_root_event.note` longer than 255 characters in older versions: check the note column first
  (Runbook Part D/F).
- Bulk import: the HPB Multiomics workbook through the Bulk Import page (synthetic patients to be revised).

## 8. Check the instance
1. Log in as Super Admin: Settings, General Definitions, Visualisation Template shows the seeded template and its panels.
2. Patient list: add a patient, add a Lab Test event with CA 19-9, open the chart button: the CA 19-9 panel shows the point.
3. Log in as Clinician and Researcher: the chart button follows `VISUALISATION_RA` (Clinician yes, Researcher no), the
   template editor is Super Admin only.
4. Medical Assessment: weight 500 is refused, 70.5 is accepted.

## Issues found by the dry run
1. ~~Histological Tumor Subtype import failed on an empty database.~~ **Fixed 2026-10-20 (V1_1_180):** the subtype `code`
   is nullable like the Type table's; all 22 rows import (8 without a code). The local database and the server get it
   when they are next deployed (the subtype list is empty there today).
2. ~~`imports_fixed.sh` reported lists filled by migrations as FAILED.~~ **Fixed 2026-10-20:** reported as "already
   present"; a failed list is still a failure.
3. **Demo roles and users stay in a "clean" instance** (Doctor, Researcher, Student and their users). For a test from
   "time zero" with only the Super Admin and the predefined roles, decide which of these a migration should still seed.
4. **T, N, M, text and secondary grade lists are not used by any form today** (see `LOOKUP_LISTS_INVENTORY.md`, section D).
5. **Seeded chart template and lookups:** fixed by V1_1_179 (the panel finds its lab test by name), but only because the
   test names CA 19-9 and Total Bilirubin exist in the imported workbook; renaming them breaks the link.
