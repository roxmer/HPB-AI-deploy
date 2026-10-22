-- Sampling authorities and the lookup-list rule for ALL roles (2026-10-13). Idempotent: running it again changes nothing.
--
-- Run AFTER the app was deployed with migrations V1_1_169, V1_1_170 and V1_1_171, and after update_role_clinician_2026-10-07.sql and
-- update_role_researcher_2026-10-09.sql. Log in again afterwards: role changes apply at the next login.
--
-- RULE 1 (Roxana, 2026-10-13): ONLY Super Admin can modify the lookup lists, and only Super Admin sees the
--   SETTINGS and Role Management menus. Other roles can USE the lists (their X_RA authority stays) but never
--   see the menu entry (X) or create / update / delete list values (X_C, X_U, X_D).
--   -> for every role except Super Admin: remove X, X_C, X_U, X_D of every authority used by a page under the
--      SETTINGS or Role Management menu (the 81 titles below are exactly the 'authority' values of those pages
--      in static/js/util/NavUtil.js). USER_RA, CORPORAL_LOCATION_RA etc. stay, so forms keep their dropdowns.
--
-- RULE 2 (Roxana, 2026-10-13): Clinician and Researcher work with Blood Sampling and Tissue Sampling (the
--   difference between them is access to patients' sensitive personal data, not these).
--   -> they get all authorities of the sampling data (BLOOD_SAMPLE*, EVENT_BLOOD_SAMPLING*, TISSUE_SAMPLING*)
--      and only the READ authority of the lists the sampling forms use (Freezer, blood tube / process types,
--      tissue process types, NGS panel).
--
-- RULE 3 (Roxana, 2026-10-13): Researcher works with samples, analyses, results and Blood / Tissue Sampling
--   events ONLY. Other event types (pathology, radiology, medical assessment, systemic therapy, ...) are created
--   by Clinician / Super Admin or by Bulk Import (Clinician / Super Admin), and are neither visible nor usable
--   for a Researcher, because event data can identify a patient.
--   Needs migration V1_1_170 (per-event-type authorities EVENT_<TYPE>_RA/_C/_U/_D, enforced by the backend):
--   -> Researcher gets EVENT_C / EVENT_U (the general gate) plus EVENT_BLOOD_SAMPLING_* and
--      EVENT_TISSUE_SAMPLING_* (RA, C, U, D), and NO per-type authority of any other event type.
--   -> Researcher loses the log MENU pages (Event, Sub-event, Patient, Medical history, Family history) and the
--      Patient / Medical history / Family history / Sub-event / Status / generic logs. It KEEPS the log cards of the
--      forms it works in: SAMPLE_LOG_RA and DIAGNOSTIC_LOG_RA (no event logs: it has no event access). Log lines hold the Patient ID, never names (code change of 2026-10-13).
--   -> Researcher has NO access to events of any type (decision 2026-10-15): no EVENT_RA / _C / _U / _D, no
--      per-type authority, no event log. Samples and diagnostics it reads carry no event details (code change),
--      and the Event menu entry and the event dropdowns disappear. Handling data of a blood / tissue sample
--      (process, storage) is entered by Clinician / lab roles. Analysis and Result are the Researcher's own work.
--   -> Researcher can create / update samples, analyses and results ONLY.
--      (a whitelist: every other create / update authority is removed, which also covers
--      patient, medical history, family history, diagnostic, radiology, test forms, sub-events, ...).
--      Diagnostics are therefore NOT creatable by Researcher: add DIAGNOSTIC_C / DIAGNOSTIC_U if the testers want it.
--   -> Researcher stays masked: PATIENT_RA (names, personal number, ...), EVENT_DATE_RA, EVENT_NOTE_RA and
--      EVENT_RESPONSIBLE_RA are removed (only Patient ID and sex are shown).
--   -> Researcher READS every lookup list (it needs them in the sample, analysis, result and sampling forms), but
--      no patient or clinical data: every read authority the Clinician has is granted EXCEPT the sensitive ones
--      listed in Rule 4 below, and the sensitive ones are removed if present (medical history, family history,
--      status, clinical data, logs, other event types, event date / note / responsible user, patient identity).
--   -> Researcher has NO delete rights at all (every authority ending in _D: events, samples, analyses,
--      results, patient data, ...): the same sample may be used by another user. Deleting is for Clinician and
--      Super Admin.
--   -> Clinician keeps every event type (V1_1_170 gave it all per-type authorities).

-- MySQL Workbench runs with "safe update mode" (error 1175 on UPDATE/DELETE without a key column in WHERE):
-- it is switched off for this script only and restored at the end.
SET @old_safe_updates := @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

-- BEFORE: per role, menu authorities (X) and modify rights (X_C/X_U/X_D) of lookup/settings pages
DROP TEMPORARY TABLE IF EXISTS tmp_menu_authority;
CREATE TEMPORARY TABLE tmp_menu_authority (title VARCHAR(255) NOT NULL PRIMARY KEY);
INSERT INTO tmp_menu_authority (title) VALUES
    ('AGE_BAND'), ('ABDOMINAL_EXAMINATION'), ('ADVERSE_REACTION_DEFINITION'), ('ANALYSIS_TYPE'),
    ('ANASTOMOSIS_TECHNIQUE_DEFINITION'), ('ASSOCIATED_TREATMENT'), ('AUTHORITY'), ('BIOPSY_TYPE'),
    ('BLOOD_SAMPLE_PROCESS_DEFINITION'), ('BLOOD_SAMPLE_TUBE_TYPE_DEFINITION'), ('CHRONIC_CONDITION'),
    ('CLINICAL_DATA'), ('CLINICAL_DIAGNOSIS'), ('CLINICAL_VARIABLE_DEFINITION'), ('CONSULTATION_TYPE'),
    ('CORPORAL_LOCATION'), ('CYTOLOGICAL_DIAGNOSIS'), ('CYTOLOGY_TYPE'), ('DIAGNOSTIC_TYPE'),
    ('DISCIPLINE'), ('ERROR_MESSAGE'), ('EVENT_ATTRIBUTE'), ('EVENT_STATUS'), ('EXTERNAL_DATA'),
    ('EXTRACTION_METHOD'), ('FREEZER'), ('GRADE'), ('HEART_EXAMINATION'),
    ('HISTOLOGICAL_TUMOR_SUBTYPE_DEFINITION'), ('HISTOLOGICAL_TUMOR_TYPE_DEFINITION'),
    ('INTERVENTION'), ('LABORATORY'), ('LAB_DRAW_ROLE'), ('LAB_TEST_DEFINITION'), ('LOCATION_TYPE'),
    ('LUNG_EXAMINATION'), ('M'), ('MAIN_GRADE_OF_DIFFERENTIATION'), ('MARGIN'),
    ('MDT_ACTION_DECISION_INTERVENTION'), ('MDT_TUMOR_CATEGORIZATION'),
    ('MORPHOLOGICAL_ANCILLARY_TEST_DEFINITION'), ('M_TEXT'), ('N'), ('N_TEXT'), ('ORGANIZATION'),
    ('ORGAN_LIST'), ('ORGAN_SYSTEM'), ('OTHER_HISTORICAL_FINDING_DEFINITION'),
    ('OTHER_RADIOLOGICAL_FINDING'), ('POSTOPERATIVE_COMPLICATION_DEFINITION'), ('PRIMARY_PARAMETER'),
    ('PROBE_TYPE'), ('PROTOCOL'), ('RADIOLOGICAL_VARIABLE_DEFINITION'), ('REFERENCE_DOCUMENT'),
    ('RELATIVE_TYPE'), ('RESECTION_MARGIN_DEFINITION'), ('RESULT_NAME'), ('RESULT_TYPE'),
    ('RISK_FACTOR'), ('ROLE'), ('SAMPLE_QUALITY'), ('SAMPLE_TYPE'),
    ('SECONDARY_GRADE_DIFFERENTIATION'), ('SEVERITY_TYPE'), ('SIGNS'), ('STATUS_TYPE'),
    ('STENT_DEFINITION'), ('SURGICAL_APPROACH_TYPE'), ('SURGICAL_PROCEDURE_DEFINITION'), ('SYMPTOMS'),
    ('SYSTEMIC_THERAPY_DEFINITION'), ('T'), ('TECHNIQUE'), ('THERAPY'), ('TISSUE_SAMPLE_NGS_PANEL'),
    ('TISSUE_SAMPLE_PROCESS_DEFINITION'), ('TREATMENT_INTENT'), ('TUMOR_REGRESSION_SYSTEM'),
    ('T_TEXT'), ('USER');

DROP TEMPORARY TABLE IF EXISTS tmp_restricted_authority;
CREATE TEMPORARY TABLE tmp_restricted_authority (authority_id BIGINT NOT NULL PRIMARY KEY);
INSERT INTO tmp_restricted_authority (authority_id)
SELECT DISTINCT a.id FROM tbl_authority a JOIN tmp_menu_authority m
  ON a.title IN (m.title, CONCAT(m.title, '_C'), CONCAT(m.title, '_U'), CONCAT(m.title, '_D'));

SELECT r.title AS role_title, COUNT(*) AS settings_rights_BEFORE
FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tmp_restricted_authority x ON x.authority_id = ra.authority_id
GROUP BY r.title;

-- Rule 1 -------------------------------------------------------------------------------------------------
DELETE ra FROM tbl_role_authority ra
JOIN tbl_role r ON r.id = ra.role_id
JOIN tmp_restricted_authority x ON x.authority_id = ra.authority_id
WHERE r.title <> 'Super Admin';

-- Rule 2: sampling data authorities (all rights) ---------------------------------------------------------
INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id FROM tbl_role r
JOIN tbl_authority a ON a.title REGEXP '^(BLOOD_SAMPLE|EVENT_BLOOD_SAMPLING|TISSUE_SAMPLING)(_(RA|C|U|D))?$'
WHERE r.title IN ('Clinician', 'Researcher')
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- Rule 2: lists used by the sampling forms (read only) ---------------------------------------------------
INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id FROM tbl_role r
JOIN tbl_authority a ON a.title IN ('FREEZER_RA', 'BLOOD_SAMPLE_PROCESS_DEFINITION_RA',
    'BLOOD_SAMPLE_TUBE_TYPE_DEFINITION_RA', 'TISSUE_SAMPLE_PROCESS_DEFINITION_RA', 'TISSUE_SAMPLE_NGS_PANEL_RA')
WHERE r.title IN ('Clinician', 'Researcher')
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- Rule 3: per-type sampling event authorities (new family from V1_1_170) for Clinician and Researcher
INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id FROM tbl_role r
JOIN tbl_authority a ON a.title REGEXP '^EVENT_(BLOOD_SAMPLING|TISSUE_SAMPLING)_(RA|C|U|D)$'
WHERE r.title IN ('Clinician', 'Researcher')
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- Rule 3: Researcher creates and edits events (general gate; the per-type authorities decide which types) --------------------------------------------------------------
INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id FROM tbl_role r JOIN tbl_authority a ON a.title IN ('EVENT_C', 'EVENT_U')
WHERE r.title = 'Researcher'
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- Rule 3: Researcher loses every per-type authority of the non-sampling event types, and the log pages
DELETE ra FROM tbl_role_authority ra
JOIN tbl_authority a ON a.id = ra.authority_id
JOIN tbl_role r ON r.id = ra.role_id
WHERE r.title = 'Researcher'
  AND (a.title REGEXP '^EVENT_(MEDICAL_ASSESSMENT|RADIOLOGY|LAB_TEST|PATHOLOGY|SYSTEMIC_THERAPY|SURGERY|VITAL_STATUS|MOLECULAR_PROFILING)_(RA|C|U|D)$'
       OR a.title REGEXP '^(PATIENT|MEDICAL_HISTORY|FAMILY_HISTORY|SUB_EVENT)_LOG(_RA)?$'
       OR a.title IN ('LOG', 'LOG_E')   -- the Logs menu group and the log export
       OR a.title REGEXP '^[A-Z_]+_LOG$'      -- every log MENU entry (the pages), the form log cards need only _RA
       OR a.title IN ('EVENT_SUB_EVENT_C', 'EVENT_SUB_EVENT_U', 'EVENT_SUB_EVENT_D')
       OR a.title IN ('PATIENT_RA', 'EVENT_DATE_RA', 'EVENT_NOTE_RA', 'EVENT_RESPONSIBLE_RA')  -- stay masked
       OR a.title IN ('MEDICAL_HISTORY', 'FAMILY_HISTORY', 'STATUS')   -- no medical / family history / status pages
       OR a.title REGEXP '^EVENT(_(MEDICAL_ASSESSMENT|RADIOLOGY|LAB_TEST|PATHOLOGY|SYSTEMIC_THERAPY|SURGERY|VITAL_STATUS|MOLECULAR_PROFILING|BLOOD_SAMPLING|TISSUE_SAMPLING))?$'  -- base event authorities
       OR a.title REGEXP '_D$'     -- no delete rights at all
       OR (a.title REGEXP '_(C|U)$'   -- create / update only on the whitelist
           AND a.title NOT REGEXP '^(SAMPLE|ANALYSIS|RESULT)_(C|U)$'));

-- Rule 4: Researcher reads the lookup lists but no patient / clinical data ----------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_researcher_no_read;
CREATE TEMPORARY TABLE tmp_researcher_no_read (authority_id BIGINT NOT NULL PRIMARY KEY);
INSERT INTO tmp_researcher_no_read (authority_id)
SELECT a.id FROM tbl_authority a WHERE a.title REGEXP
  '^(ROLE_RA|AUTHORITY_RA|EVENT_RA|EVENT_LOG_RA|EVENT_BLOOD_SAMPLING_RA|EVENT_TISSUE_SAMPLING_RA|PATIENT_RA|PATIENT_COMPLETE_REPORT_RA|EVENT_DATE_RA|EVENT_NOTE_RA|EVENT_RESPONSIBLE_RA|LOG_RA|PATIENT_LOG_RA|MEDICAL_HISTORY_LOG_RA|FAMILY_HISTORY_LOG_RA|SUB_EVENT_LOG_RA|STATUS_LOG_RA|MEDICAL_HISTORY_RA|FAMILY_HISTORY_RA|STATUS_RA|CLINICAL_DATA_RA|EXTERNAL_DATA_RA|MEDICAL_ASSESSMENT_RA|PATHOLOGY_RA|RADIOLOGY_RA|SYSTEMIC_THERAPY_RA|LAB_TEST_RA|LAB_TEST_RESULT_RA|TEST_FORM_RA|TEST_RESULT_RA|EVENT_(MEDICAL_ASSESSMENT|RADIOLOGY|LAB_TEST|PATHOLOGY|SYSTEMIC_THERAPY|SURGERY|VITAL_STATUS|MOLECULAR_PROFILING)_RA)$';

DELETE ra FROM tbl_role_authority ra
JOIN tbl_role r ON r.id = ra.role_id
JOIN tmp_researcher_no_read x ON x.authority_id = ra.authority_id
WHERE r.title = 'Researcher';

INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id
FROM tbl_role r
JOIN tbl_role cl ON cl.title = 'Clinician'
JOIN tbl_role_authority c ON c.role_id = cl.id
JOIN tbl_authority a ON a.id = c.authority_id
WHERE r.title = 'Researcher'
  AND a.title LIKE '%\_RA'
  AND a.id NOT IN (SELECT authority_id FROM tmp_researcher_no_read)
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- CHECKS ---------------------------------------------------------------------------------------------------
-- 1. must be 0 rows: a role other than Super Admin that still has a settings / role management right
SELECT r.title AS role_title, a.title AS must_be_empty
FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tmp_restricted_authority x ON x.authority_id = ra.authority_id
JOIN tbl_authority a ON a.id = ra.authority_id
WHERE r.title <> 'Super Admin';

-- 2. must be 0 rows: sampling authority that Clinician or Researcher is missing
SELECT r.title AS role_title, a.title AS missing_authority
FROM tbl_role r JOIN tbl_authority a ON a.title REGEXP
  '^(BLOOD_SAMPLE|EVENT_BLOOD_SAMPLING|TISSUE_SAMPLING)(_(RA|C|U|D))?$|^(FREEZER_RA|BLOOD_SAMPLE_PROCESS_DEFINITION_RA|BLOOD_SAMPLE_TUBE_TYPE_DEFINITION_RA|TISSUE_SAMPLE_PROCESS_DEFINITION_RA|TISSUE_SAMPLE_NGS_PANEL_RA)$'
WHERE r.title IN ('Clinician', 'Researcher')
  AND NOT (r.title = 'Researcher' AND a.title REGEXP '_D$')   -- Researcher has no delete rights (Rule 3)
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- 3. must be 0 rows: Clinician or Researcher can modify a list that the sampling forms use
SELECT r.title AS role_title, a.title AS must_be_empty
FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id JOIN tbl_authority a ON a.id = ra.authority_id
WHERE r.title IN ('Clinician', 'Researcher')
  AND a.title REGEXP '^(FREEZER|BLOOD_SAMPLE_PROCESS_DEFINITION|BLOOD_SAMPLE_TUBE_TYPE_DEFINITION|TISSUE_SAMPLE_PROCESS_DEFINITION|TISSUE_SAMPLE_NGS_PANEL)(_(C|U|D))?$';

-- 4. Researcher event rights. Expected only the read-only lists EVENT_ATTRIBUTE_RA, EVENT_STATUS_RA, EVENT_TYPE_RA
--    (no EVENT_RA, no per-type event authority)
SELECT a.title AS researcher_event_rights FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id
WHERE r.title = 'Researcher' AND a.title REGEXP '^EVENT_(RA|C|U|D|[A-Z_]+_(RA|C|U|D))$' ORDER BY a.title;

-- 4b. must be 0 rows: Researcher with any delete right
SELECT a.title AS researcher_delete_right FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id WHERE r.title = 'Researcher' AND a.title REGEXP '_D$';

-- 4c. Researcher create / update rights. Expected exactly: ANALYSIS_C/_U, RESULT_C/_U, SAMPLE_C/_U
SELECT a.title AS researcher_create_update_rights FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id WHERE r.title = 'Researcher' AND a.title REGEXP '_(C|U)$' ORDER BY a.title;

-- 4d. must be 0 rows: a sensitive read right still held by Researcher
SELECT a.title AS researcher_sensitive_read FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id JOIN tmp_researcher_no_read x ON x.authority_id = a.id
WHERE r.title = 'Researcher';

-- 4e. for review: every read authority the Researcher now has (should be lookup lists, samples, analyses, results,
--     diagnostics, sampling events)
SELECT a.title AS researcher_read_rights FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id WHERE r.title = 'Researcher' AND a.title LIKE '%\\_RA' ORDER BY a.title;

-- 4f. Researcher log rights. Expected exactly: DIAGNOSTIC_LOG_RA, SAMPLE_LOG_RA
SELECT a.title AS researcher_log_rights FROM tbl_role r JOIN tbl_role_authority ra ON ra.role_id = r.id
JOIN tbl_authority a ON a.id = ra.authority_id WHERE r.title = 'Researcher' AND a.title REGEXP '(^|_)LOG(_|$)' ORDER BY a.title;

-- 5. must be 0 rows: Clinician missing a per-type authority (it must have all 40)
SELECT a.title AS clinician_missing FROM tbl_authority a
WHERE a.title REGEXP '^EVENT_(MEDICAL_ASSESSMENT|RADIOLOGY|LAB_TEST|PATHOLOGY|SYSTEMIC_THERAPY|SURGERY|BLOOD_SAMPLING|TISSUE_SAMPLING|VITAL_STATUS|MOLECULAR_PROFILING)_(RA|C|U|D)$'
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x JOIN tbl_role r ON r.id = x.role_id
                  WHERE r.title = 'Clinician' AND x.authority_id = a.id);

SET SQL_SAFE_UPDATES = @old_safe_updates;
