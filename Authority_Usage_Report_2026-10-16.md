# Authority usage report (2026-10-16)

Comparison of the authorities in the database with every quoted authority name in `src/main` (Java annotations, `hasAuthority(...)`, JavaScript, HTML and the menu in `NavUtil.js`), plus the per-event-type family `EVENT_<TYPE>_RA/C/U/D` that `EventTypeAccess` assembles at run time.

- Authorities in the database: **715**
- Referenced by the application: **669**
- **Not referenced anywhere: 46** (removal candidates, to be reviewed)

**How to read it.** Super Admin holds every authority, so being held by a role says nothing about use. Only authorities that no code or menu refers to are candidates. If an authority is assembled from parts in some other place, it could show up here by mistake: check each group once before it is deleted (the removal script is only written after your review).

## Not referenced anywhere

| Group | Authorities | Held by a role other than Super Admin |
|---|---|---|
| ALLOWED_VALUE | (base) | Clinician, Researcher |
| ANALYSIS_STATUS | (base) | Clinician, Researcher |
| AUTHORITY | _C, _D, _U | - |
| CODING_SYSTEM_AND_VERSION | (base), _RA | Clinician, Researcher |
| COUNTY | (base), _C, _D, _RA, _U | Clinician, Researcher |
| EVENT | (base) | Clinician |
| EVENT_BLOOD_SAMPLING | (base) | Clinician |
| EVENT_MEDICAL_ASSESSMENT | (base) | Clinician |
| EVENT_RADIOLOGY | (base) | Clinician |
| EVENT_SURGERY | (base) | Clinician |
| EXTERNAL_LINK | _C | Clinician |
| HELP_DOCUMENT | (base) | Clinician, Researcher |
| HISTOLOGICAL_TUMOR_SUBTYPE_DEFINITION | _RA | Clinician, Researcher |
| HISTOLOGICAL_TUMOR_TYPE_DEFINITION | _RA | Clinician, Researcher |
| LOG | (base) | Clinician |
| MDT_ACTION_DECISION_INTERVENTION | _RA | Clinician, Researcher |
| MDT_TUMOR_CATEGORIZATION | _RA | Clinician, Researcher |
| MULTI_LANG_MESSAGE | _C, _D | Clinician |
| RESECTION_TYPE | (base) | Clinician, Researcher |
| TEST_FORM | (base), _RA | Clinician, Researcher |
| TEST_NAME | (base), _RA | Clinician, Researcher |
| TEST_RESULT | (base), _RA | Clinician, Researcher |
| TEST_UNIT | (base), _RA | Clinician, Researcher |
| TNM_PARAMETER_REFERENCE | (base), _C, _D, _RA, _U | Clinician, Researcher |
| TNM_REFERENCE | (base), _C, _D, _RA, _U | Clinician, Researcher |
| TUBE_TYPE | (base) | Clinician, Researcher |
