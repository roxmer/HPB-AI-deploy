# Lookup lists: which ones the application uses, and where each list comes from

Revised 2026-10-20. "Used" means a form, a dropdown or the server logic reads the list (checked in `11.-HPB`: the JS
forms, the entities and the services), not just that a Settings page exists for it. Evidence is code reading plus a dry
run on an empty database (200 migrations, then `./imports_fixed.sh import.csv`: 50 imported, 8 already present, 0 failed).
When the application has been tested thoroughly, the lists marked "no form uses it today" are the candidates for
cleaning the `HPB_Templates` folder and the SETTINGS menu.

## A. Imported by `import.csv` (58 rows, one Excel file each in `HPB_Templates/`)
Imported through the application's own API, in the order of the file. Four rows import a workbook with several sheets
through `data-import-all`: **technique** (technique, test name, test result, test unit), **organ-list** (organ list and
resection type), **primary-parameter** (primary parameters and their allowed values). `laboratory` was added on
2026-10-20 (`Laboratory_export.xlsx`: Laboratory 1 to Laboratory 5, rename them before importing or later in Settings)
`performance-status` on 2026-10-21 (`PerformanceStatus_export.xlsx`, the Medical Assessment performance status list), and `discipline` on 2026-10-21 (`Discipline_export.xlsx`, 7 rows; 6 are also seeded by a migration, so the import adds the rest).
Only **Event Type** is meant to stay migration-only: the application depends on its 10 fixed event types.

## B. Filled by the database migrations (no import needed; Super Admin can edit them in Settings)
Age Band (16), Analysis Status (3), Assessment Purpose (3), Blood Sample Process (2), Blood Sample Tube Type (2),
Discipline (6, also imported), Event Status (3), Event Type (10, migration only), Performance Status (6, V1_1_181: ECOG 0 to 4 and Not documented; also in `import.csv`), Extraction Method (8), Freezer (2), Lab Draw Role (3), MDK Flow (5),
Organization (4), Panel Context (5), Patient Flow (5), Provenance (3), Radiologist Assessment (6), Radiology Other Role (5),
Reference Document (1), Reviewer Pattern (5), Route to Diagnosis (5), Sample Quality (3), Sample Type (2), Stent (3),
Surgical Approach (3), Surgical Procedure (30), Tissue Sample Process (7), Treatment Intent (4).
Some of these also have a row in `import.csv` (Analysis Status, Blood Sample Process, Blood Sample Tube Type,
Extraction Method, Panel Context, Assessment Purpose, Lab Draw Role, Freezer, Sample Type, Organization): on a new
instance the import reports "already present" for most, or adds the extra rows (Sample Type, Organization).

## C. Used, in no `import.csv` row on purpose
| List | Why |
|---|---|
| Allowed Value | imported as a sheet of `PrimaryParameter_data_export_all.xlsx` (organized by primary parameter); `AllowedValue_export.xlsx` alone lacks the parent column the importer needs, so it is a legacy file |
| Resection Type | imported as a sheet of `OrganList_Resection_Type_export.xlsx` |
| Test name / result / unit | imported as sheets of `Technique_TestName_TestResult_TestUnit_export.xlsx` |
| Event Type | filled by migrations (section B) and deliberately **not** imported; the Excel file is a reference copy |
| **TNM staging** (T, N, M, L, V, Pn, R) | used by the Pathology resection sub-event when the Location Type is "Primary Tumor". It runs on **Primary Parameters** (T, N, M, L, V, Pn, R) with their **Allowed Values** (9, 4, 2, 2, 2, 2, 4 values), imported from `PrimaryParameter_data_export_all.xlsx` |

## D. No form uses it today (check, then keep or remove after the test phase)
Found only on their own Settings page, with no dropdown, entity link or service reading them:
- **Event Attribute**
- **T, N, M descriptions** (`Description_T/N/M_export.xlsx`) and **T, N, M texts** (`TText/NText/MText_export.xlsx`; the
  texts workbooks are empty): the TNM staging does NOT read them, it reads Primary Parameter and Allowed Value (section C)
- **Secondary Grade of Differentiation** (`SecondaryGradeDifferentiation.xlsx`)
- **Tissue Sample NGS Panel**, **Tube Type**
- **Coding System Version**
These are not in `import.csv`.

**Grade and Severity Type** (Settings, Event Management / Staging & Grading) have the same content since 2026-10-20
(1 mild to 5 death). The Grade list is read by three places with different meanings: the adverse-reaction grade
(Medical Assessment), the **biopsy grade** and the **resection grade** (Pathology). Tumour grading and adverse-event
grading are different concepts: to be decided (see the Settings menu discussion).

## E. Files in `HPB_Templates/` that no import row reads
`AllowedValue_export.xlsx`, `CodingSystemVersion_export.xlsx`, `Description_M/N/T_export.xlsx`, `Discipline_export.xlsx`,
`Event_Type_export.xlsx`, `MText/NText/TText_export.xlsx`, `ResectionType_export.xlsx`,
`SecondaryGradeDifferentiation.xlsx`, `Resection margins HPB.xlsx`, `Resection margins HPB - corrected.xlsx`
(superseded by `ResectionMarginDefinition_export.xlsx`), the two documentation `.docx` files and `~$Grade_export.xlsx`
(a temporary lock file that Excel leaves while `Grade_export.xlsx` is open: delete it after closing Excel).

## F. Lists that are not lookups but have an import endpoint
Patient data and events (analysis, sample, diagnostic, event, radiology, pathology, medical assessment, systemic
therapy, lab test, lab test result, blood and tissue sampling, family history, status, clinical data, external data,
MDT decisions): imported through the Bulk Import page or their own pages, not through `import.csv`.
