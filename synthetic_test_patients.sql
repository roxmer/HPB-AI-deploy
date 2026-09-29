-- ============================================================================
-- SYNTHETIC TEST PATIENTS for HPB Registry (5 patients)
-- ============================================================================
-- Purpose: diversify AI Assistant / workflow testing beyond patient "Pedro
-- Paramo" (id resolved dynamically below, not hardcoded) with a spread of
-- HPB cancer types and event workflows:
--   - Medical history + Family history on every patient
--   - Pathology events with BIOPSY, CYTOLOGY, and RESECTION sub-events
--     (each patient gets exactly one sub-event type, so all three are
--     covered across the 5 patients)
--   - Lab tests linked directly to a pathology sub-event (tbl_test_form.sub_event_id)
--     AND standalone Lab Test events (tbl_test_form.lab_test_id)
--   - Medical Assessment events (vitals, ECOG PS, note)
--   - A tbl_diagnostic record anchored to the pathology event, and a
--     tbl_status record (patient-level condition note)
--
-- All lookup values below are referenced by NAME via subquery (not raw
-- numeric IDs), so this script is robust to whatever the actual
-- auto-increment IDs are in your local DB after the Excel imports. Every
-- name was verified against the real HPB_Templates/*.xlsx exports and the
-- Java entities in 11.-HPB, not guessed.
--
-- ONE KNOWN SCHEMA GAP, flagged rather than worked around silently:
-- EventMedicalAssessmentEntity requires a non-null adverse_reaction_id and
-- severity_id, but the Adverse_Reaction.xlsx lookup list has no "None /
-- No adverse reaction" row -- every medical assessment is forced to cite
-- some real adverse event even for a routine, uneventful visit. Below I
-- use a mild, plausible finding (Grade 1 Fatigue/Asthenia) as the least
-- misleading stand-in. Worth adding a real "None reported" row to
-- Adverse_Reaction.xlsx and re-importing if this bothers you.
--
-- Run this against your local HPB MySQL database (the same one
-- deploy_hpb_local.sh points at). Review before running -- as always,
-- back up / use a disposable local DB copy first.
--
-- AUDIT TRAIL (created_by / modified_by): every tbl_* table here extends the
-- app's CommonEntity base and has nullable created_by/modified_by BIGINT
-- columns. In the running app these are stamped automatically by Spring Data
-- JPA auditing (@CreatedBy/@LastModifiedBy) with the logged-in user's id --
-- but raw SQL INSERTs bypass that entirely, so every row this script creates
-- would otherwise have created_by/modified_by = NULL, unlike anything
-- entered through the UI. Below, @app_user_id is inserted into every row's
-- created_by/modified_by, using the same user id already used for
-- responsible_user_id throughout this script (id 2) so the "responsible
-- clinician" and "logged-in user who entered it" are the same person, as
-- they would be in a real single-user data-entry session. Change
-- @app_user_id if you want the synthetic rows attributed to a different
-- seeded tbl_user id.
--
-- Separately, the app also writes to dedicated audit-log tables that feed
-- the Logs UI page (tbl_patient_log, tbl_medical_history_log,
-- tbl_family_history_log, tbl_status_log, tbl_event_log, tbl_sub_event_log,
-- tbl_diagnostic_log). Those are populated by explicit Java service calls
-- (PatientLogService / EventLogService / DiagnosticLogService / etc.), not
-- by JPA auditing, so raw SQL never triggers them either. This script now adds
-- one matching log row immediately after each corresponding entity insert
-- (patient, medical history, family history, pathology/lab
-- test/medical-assessment/surgery events, sub-events, diagnostic, status),
-- so the Logs page shows an entry for each. Descriptions are simplified,
-- human-written summaries rather than exact copies of the app's generated
-- text -- the important part (table, entity_type, entity_id/event_id
-- linkage, action_type, created_by) matches what the app would produce.
-- ============================================================================
SET @app_user_id = 2;


-- ============================================================================
-- PATIENT 1: Elena Kowalski -- Hepatocellular Carcinoma (HCC), biopsy-confirmed
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Elena', 'Kowalski', (TO_DAYS('1965-03-14') - TO_DAYS('1970-01-01')) * 86400000, 'FEMALE', '196503141234',
        'SYN-P0001',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p1 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p1, 'CREATE', 'Created patient: Elena Kowalski (Personal #: 196503141234)');


-- Medical history: HBV-related cirrhosis background
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1);
SET @p1_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p1_mh, 'CREATE', 'Created medical history for patient: Elena Kowalski with 1 diagnosis (Hepatocellular carcinoma), 2 chronic conditions, 1 risk factor');


INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Chronic Viral Hepatitis (HBV, HCV)')),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Cirrhosis (Liver Fibrosis)'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Hepatocellular carcinoma'), '61', NULL);

INSERT INTO tbl_medical_history_risk_factor (created_date, modified_date, created_by, modified_by, medical_history_id, risk_factor_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_mh, (SELECT id FROM tbl_risk_factor WHERE risk_factor LIKE 'Chronic hepatitis B infection%'));

-- Family history: mother died of HCC
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1, (SELECT id FROM tbl_relative_type WHERE name = 'Mother'), 70);
SET @p1_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p1_fh, 'CREATE', 'Created family history entry for patient: Elena Kowalski -- Mother, died age 70 of Hepatocellular carcinoma');


INSERT INTO tbl_family_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, family_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_fh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Hepatocellular carcinoma'), '65', '70');

-- Pathology event -> BIOPSY sub-event (percutaneous core needle biopsy of liver mass)
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Biopsy-confirmed', 0, 0);
SET @p1_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-06-01')*1000,
        2, @p1,
        'Ultrasound-guided percutaneous core needle biopsy of a 4.2 cm segment VII liver mass, performed for a new hypervascular lesion on surveillance imaging in a patient with known HBV-related cirrhosis. Procedure tolerated well, no post-procedure bleeding.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p1_path);
SET @p1_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p1_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Elena Kowalski');


INSERT INTO tbl_sub_event_biopsy (created_date, modified_date, created_by, modified_by, corporal_location_id, biopsy_type_id, location_type_id, histological_type_id, event_date, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Liver%'),
        (SELECT id FROM tbl_biopsy_type WHERE name LIKE 'Percutaneous Core Needle Biopsy%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name LIKE 'Hepatocellular Carcinoma%'),
        UNIX_TIMESTAMP('2026-06-01')*1000, 2);
SET @p1_biopsy = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_path, 'PATHOLOGY', @p1_biopsy, 'BIOPSY');
SET @p1_biopsy_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p1_path_root, @p1_biopsy_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created BIOPSY sub-event for parent PATHOLOGY event');


-- Lab test (AFP) linked directly to the biopsy sub-event
INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, sub_event_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_biopsy_link,
        (SELECT id FROM tbl_technique WHERE name = 'Immunoassay (ELISA)'),
        (SELECT id FROM tbl_test_name WHERE name = 'AFP'),
        (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'AFP')),
        (SELECT id FROM tbl_test_unit WHERE unit = 'ng/mL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'AFP')),
        '612', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'),
        'Markedly elevated AFP is consistent with the biopsy-confirmed diagnosis of HCC.');

-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Liver cell carcinoma'), UNIX_TIMESTAMP('2026-06-03')*1000,
        @p1, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 3%'), 2,
        'Biopsy-confirmed hepatocellular carcinoma arising on a background of HBV-related cirrhosis (Child-Pugh A). Discussed at HPB MDT; underlying liver disease precludes resection -- referred for trans-arterial chemoembolization (TACE) evaluation.',
        0, 1, 0);
SET @p1_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p1_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Liver cell carcinoma (biopsy-confirmed HCC)');


-- Link diagnostic to its originating event (tbl_diagnostic no longer stores event_id directly as of the 2026-07-29 "diagnostic update" migration -- linkage now goes through tbl_diagnostic_event)
INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_diag, @p1_path_root);

-- Standalone Lab Test event: liver function panel + HBsAg
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p1_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-06-10')*1000,
        2, @p1, 'Routine liver function panel and hepatitis serology ahead of TACE work-up.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p1_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p1_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Routine liver function panel and hepatitis serology ahead of TACE work-up');


INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_lab, (SELECT id FROM tbl_technique WHERE name = 'Colorimetric / Spectrophotometric'),
  (SELECT id FROM tbl_test_name WHERE name = 'AST'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'AST')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'AST')),
  '78', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Mild transaminitis, consistent with underlying cirrhosis.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_lab, (SELECT id FROM tbl_technique WHERE name = 'Bromcresol dye-binding assay'),
  (SELECT id FROM tbl_test_name WHERE name = 'Albumin'),
  (SELECT id FROM tbl_test_result WHERE name = 'Decreased' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Albumin')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'g/dL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Albumin')),
  '3.1', 'L', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Reduced synthetic function, in keeping with Child-Pugh A cirrhosis.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1_lab, (SELECT id FROM tbl_technique WHERE name = 'ELISA / CLIA'),
  (SELECT id FROM tbl_test_name WHERE name = 'HBsAg'),
  (SELECT id FROM tbl_test_result WHERE name = 'Positive' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'HBsAg')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'N/A' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'HBsAg')),
  'Reactive', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Confirms chronic active HBV infection, the driver of this patient''s cirrhosis and HCC.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '165', '61', '118/76', '78', '36.7',
        'Follow-up oncology visit two weeks after liver biopsy. Patient reports mild fatigue but is otherwise well, tolerating oral intake, no new jaundice or abdominal pain. Plan: proceed with TACE work-up as per MDT recommendation.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Fatigue / Asthenia / Malaise'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Medical Oncologist'),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '22.4');
SET @p1_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-06-15')*1000,
        2, @p1, 'Routine post-biopsy oncology follow-up visit.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p1_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p1_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Routine post-biopsy oncology follow-up visit');


-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p1, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-06-15')*1000,
        '165', '61', 'Alive with active, unresectable HCC on a background of HBV cirrhosis (Child-Pugh A); undergoing work-up for locoregional (TACE) therapy.', 2);
SET @p1_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p1_status, 'CREATE', 'Created status: Alive with active, unresectable HCC on HBV cirrhosis background');



-- ============================================================================
-- PATIENT 2: Björn Andersson -- Pancreatic Ductal Adenocarcinoma (PDAC),
--            status post Whipple resection
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Björn', 'Andersson', (TO_DAYS('1958-09-22') - TO_DAYS('1970-01-01')) * 86400000, 'MALE', '195809221234',
        'SYN-P0002',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p2 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p2, 'CREATE', 'Created patient: Bjorn Andersson (Personal #: 195809221234)');


-- Medical history: chronic pancreatitis, T2DM, long smoking history
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2);
SET @p2_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p2_mh, 'CREATE', 'Created medical history for patient: Bjorn Andersson with 3 diagnoses, 3 chronic conditions, 0 risk factors');


INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Chronic Pancreatitis')),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Type 2 Diabetes Mellitus')),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Smoking History'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Chronic pancreatitis'), '52', NULL),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Type 2 diabetes mellitus without complications'), '60', NULL),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of head of pancreas'), '68', NULL);

-- Family history: father died of pancreatic cancer
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2, (SELECT id FROM tbl_relative_type WHERE name = 'Father'), 71);
SET @p2_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p2_fh, 'CREATE', 'Created family history entry for patient: Bjorn Andersson -- Father, died age 71 of pancreatic head malignancy');


INSERT INTO tbl_family_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, family_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_fh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of head of pancreas'), '69', '71');

-- Pathology event -> RESECTION sub-event (Whipple / pancreaticoduodenectomy)
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Surgical resection specimen', 1, 0);
SET @p2_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-05-20')*1000,
        2, @p2,
        'Pancreaticoduodenectomy (Whipple procedure) performed after 2 cycles of neoadjuvant FOLFIRINOX for a resectable pancreatic head mass. Surgical and pathologic margins assessed on the resection specimen.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p2_path);
SET @p2_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p2_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Bjorn Andersson');


-- NOTE on fields intentionally left NULL below: tbl_allowed_value (used for
-- t/n/m_parameter_id) currently only contains T/N/M staging codes -- there
-- are no L (lymphovascular), V (venous), Pn (perineural), or R (margin)
-- codes in that table at all, so l/v/pn/r_parameter_id have nothing to
-- reference; margin/perineural/lymphovascular status is captured in the
-- free-text description instead. Every other field below IS filled.
INSERT INTO tbl_sub_event_resection (created_date, modified_date, created_by, modified_by, resection_type_id, organ_list_id, corporal_location_id, location_type_id, histological_tumor_type_definition_id, main_grade_of_differentiation_id, event_date, number_of_tumors, largest_tumor_diameter, satellitosis, number_of_regional_lymph_nodes_examined, number_of_regional_lymph_nodes_with_metastasis, number_of_distant_lymph_nodes_examined, number_of_distant_lymph_nodes_with_metastasis, tumor_regression_system_id, tumor_regression_value, t_parameter_id, n_parameter_id, m_parameter_id, description, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_resection_type WHERE name = 'Pancreaticoduodenectomy (Whipple)'),
        (SELECT id FROM tbl_organ_list WHERE title = 'Pancreas'),
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Pancreas%Head%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name LIKE 'Pancreatic Ductal Adenocarcinoma%'),
        (SELECT id FROM tbl_main_grade_of_differentiation WHERE title LIKE 'G2%'),
        UNIX_TIMESTAMP('2026-05-20')*1000, 1, 32, 0, 18, 2, 0, 0,
        (SELECT id FROM tbl_tumor_regression_system WHERE title = 'Partial Response'),
        'Moderate treatment effect (CAP grade 2) after neoadjuvant FOLFIRINOX',
        (SELECT id FROM tbl_allowed_value WHERE title = 'T2'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'N1'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'M0'),
        'Pancreaticoduodenectomy: 3.2 cm invasive ductal adenocarcinoma, head of pancreas. Uncinate (SMA) margin clear by 1.5 mm -- R0. 2/18 nodes involved. Perineural invasion present, no lymphovascular invasion.',
        2);
SET @p2_resection = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_path, 'PATHOLOGY', @p2_resection, 'RESECTION');
SET @p2_resection_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p2_path_root, @p2_resection_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created RESECTION sub-event for parent PATHOLOGY event');


-- SURGERY event: the operative encounter itself (distinct from the pathology
-- specimen data above -- this is where the R0/R1/R2 margin status has its
-- own dedicated structured field, tbl_event_surgery.surgical_r_status,
-- rather than only living in the resection's free-text description).
INSERT INTO tbl_event_surgery (created_date, modified_date, created_by, modified_by, operation_intent, preop_porta_venous_embolization, surgical_approach, conversion, operative_time, estimated_blood_loss, transfusion_volume, surgical_r_status, length_perop_hospital_stay, postop_readmission, postop_readmission_reason, postop_length_of_stay)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Curative', 0, 'Open', 0, '410', '450', '0', 'R0', '1', 'No', 'N/A', '9');
SET @p2_surgery = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), UNIX_TIMESTAMP('2026-05-20')*1000,
        2, @p2,
        'Open pancreaticoduodenectomy (Whipple procedure) after neoadjuvant FOLFIRINOX. Operative time ~7 hours, estimated blood loss 450 mL, no transfusion required. R0 resection achieved. Uneventful post-operative course, no readmission.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p2_surgery);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p2_surgery, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), 'Created event | Type: SURGERY | Patient: Bjorn Andersson');


-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Malignant neoplasm of head of pancreas'), UNIX_TIMESTAMP('2026-05-25')*1000,
        @p2, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 2%'), 2,
        'ypT2N1, R0-resected pancreatic ductal adenocarcinoma of the head of pancreas following neoadjuvant FOLFIRINOX and Whipple resection. Adjuvant chemotherapy planned per MDT.',
        0, 1, 0);
SET @p2_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p2_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Malignant neoplasm of head of pancreas (Whipple resection, ypT2N1 R0)');


-- Link diagnostic to its originating event (tbl_diagnostic no longer stores event_id directly as of the 2026-07-29 "diagnostic update" migration -- linkage now goes through tbl_diagnostic_event)
INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_diag, @p2_path_root);

-- Standalone Lab Test event: tumor markers
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p2_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-06-20')*1000,
        2, @p2, 'Post-operative tumor marker check, 4 weeks after Whipple resection, prior to starting adjuvant chemotherapy.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p2_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p2_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Post-operative tumor marker check ahead of adjuvant chemotherapy');


INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_lab, (SELECT id FROM tbl_technique WHERE name = 'ECLIA or ELISA'),
  (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/mL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  '19', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Normalized post-resection, favorable prognostic sign.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2_lab, (SELECT id FROM tbl_technique WHERE name = 'Colorimetric enzymatic assay'),
  (SELECT id FROM tbl_test_name WHERE name = 'Lipase'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Lipase')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Lipase')),
  '28', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'No evidence of pancreatic leak.');

-- Medical Assessment event: post-op follow-up
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '178', '74', '132/84', '72', '36.8',
        'Four-week post-operative surgical follow-up after Whipple resection. Wound healing well, no signs of pancreatic fistula or infection. Mild new-onset steatorrhea, started on pancreatic enzyme replacement. Cleared to proceed with adjuvant chemotherapy.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Abdominal Pain'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Surgical Oncologist / Surgeon'),
        (SELECT id FROM tbl_discipline WHERE title = 'Surgeon'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '23.4');
SET @p2_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-06-20')*1000,
        2, @p2, 'Four-week post-Whipple surgical follow-up.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p2_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p2_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Four-week post-Whipple surgical follow-up');


-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p2, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-06-20')*1000,
        '178', '74', 'Alive, R0-resected pancreatic head adenocarcinoma (ypT2N1) status post neoadjuvant FOLFIRINOX and Whipple resection; recovering well, about to start adjuvant chemotherapy.', 2);
SET @p2_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p2_status, 'CREATE', 'Created status: Alive, R0-resected PDAC status post Whipple resection');



-- ============================================================================
-- PATIENT 3: Margit Larsson -- Perihilar Cholangiocarcinoma (Klatskin tumor),
--            cytology-confirmed via ERCP brush cytology
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Margit', 'Larsson', (TO_DAYS('1952-01-30') - TO_DAYS('1970-01-01')) * 86400000, 'FEMALE', '195201301234',
        'SYN-P0003',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p3 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p3, 'CREATE', 'Created patient: Margit Larsson (Personal #: 195201301234)');


-- Medical history: primary sclerosing cholangitis (PSC), the classic risk factor
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3);
SET @p3_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p3_mh, 'CREATE', 'Created medical history for patient: Margit Larsson with 1 diagnosis, 1 chronic condition, 0 risk factors');


INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Primary Sclerosing Cholangitis (PSC)'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of extrahepatic bile duct'), '74', NULL);

-- Family history: sister with colorectal cancer (unrelated but realistic)
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3, (SELECT id FROM tbl_relative_type WHERE name = "Sister (on the mother's side)"), NULL);
SET @p3_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p3_fh, 'CREATE', 'Created family history entry for patient: Margit Larsson -- Sister (maternal side), no linked HPB diagnosis on file');


-- (No clinical_diagnosis row added here since her sister is still alive with
--  no HPB-relevant diagnosis on file -- family history entry intentionally
--  minimal, to also test that the AI Assistant handles a family history
--  record with no linked diagnosis correctly.)

-- Pathology event -> CYTOLOGY sub-event (ERCP brush cytology of a biliary stricture)
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Cytology-confirmed', 0, 0);
SET @p3_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-04-18')*1000,
        2, @p3,
        'ERCP performed for progressive painless jaundice in a patient with known PSC. A dominant hilar biliary stricture was identified and brushed for cytology; biliary stent placed for decompression.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p3_path);
SET @p3_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p3_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Margit Larsson');


INSERT INTO tbl_sub_event_cytology (created_date, modified_date, created_by, modified_by, cytology_type_id, cytological_diagnosis_id, event_date, responsible_user_id, corporal_location_id, location_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_cytology_type WHERE cytology_type = 'Brush Cytology'),
        (SELECT id FROM tbl_cytological_diagnosis WHERE title = 'Perihilar Cholangiocarcinoma (pCCA) Cytology'),
        UNIX_TIMESTAMP('2026-04-18')*1000, 2,
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Extrahepatic Bile Ducts%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'));
SET @p3_cytology = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_path, 'PATHOLOGY', @p3_cytology, 'CYTOLOGY');
SET @p3_cytology_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p3_path_root, @p3_cytology_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created CYTOLOGY sub-event for parent PATHOLOGY event');


-- Lab test (CA 19-9) linked directly to the cytology sub-event
INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, sub_event_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_cytology_link,
        (SELECT id FROM tbl_technique WHERE name = 'ECLIA or ELISA'),
        (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9'),
        (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
        (SELECT id FROM tbl_test_unit WHERE unit = 'U/mL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
        '284', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'),
        'Markedly elevated, supportive of the cytology-confirmed cholangiocarcinoma diagnosis.');

-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Malignant neoplasm of extrahepatic bile duct'), UNIX_TIMESTAMP('2026-04-22')*1000,
        @p3, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 3%'), 2,
        'Brush cytology-confirmed perihilar cholangiocarcinoma (Klatskin, Bismuth-Corlette IIIa) on a background of PSC. Unresectable given bilateral biliary involvement -- referred for palliative chemotherapy.',
        0, 1, 0);
SET @p3_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p3_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Malignant neoplasm of extrahepatic bile duct (Klatskin, cytology-confirmed)');


-- Link diagnostic to its originating event (tbl_diagnostic no longer stores event_id directly as of the 2026-07-29 "diagnostic update" migration -- linkage now goes through tbl_diagnostic_event)
INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_diag, @p3_path_root);

-- Standalone Lab Test event: obstructive liver panel
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p3_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-04-17')*1000,
        2, @p3, 'Liver panel obtained on admission for jaundice, prior to ERCP.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p3_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p3_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Liver panel obtained on admission for jaundice, prior to ERCP');


INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_lab, (SELECT id FROM tbl_technique WHERE name = 'Enzymatic / Immunoinhibition assay'),
  (SELECT id FROM tbl_test_name WHERE name = 'GGT'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'GGT')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'GGT')),
  '412', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Markedly elevated, consistent with biliary obstruction.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3_lab, (SELECT id FROM tbl_technique WHERE name = 'Spectrophotometric diazo assay'),
  (SELECT id FROM tbl_test_name WHERE name = 'Total Bilirubin'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Total Bilirubin')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'mg/dL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'Total Bilirubin')),
  '8.4', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Obstructive-pattern jaundice, prompted urgent ERCP.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 1, '160', '58', '128/78', '84', '37.1',
        'Referred urgently for painless jaundice and pruritus of two weeks'' duration. Scleral icterus and mild right-upper-quadrant tenderness on exam. Admitted for ERCP.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 2%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Pain (general)'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Pathologist'),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '22.7');
SET @p3_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-04-16')*1000,
        2, @p3, 'Admission assessment for obstructive jaundice, prior to ERCP.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p3_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p3_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Admission assessment for obstructive jaundice, prior to ERCP');


-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p3, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-04-22')*1000,
        '160', '58', 'Alive with active, unresectable perihilar cholangiocarcinoma on a background of PSC; biliary stent in place, starting palliative systemic chemotherapy.', 2);
SET @p3_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p3_status, 'CREATE', 'Created status: Alive with active, unresectable perihilar cholangiocarcinoma on PSC background');



-- ============================================================================
-- PATIENT 4: Ahmed Al-Hassan -- Gallbladder adenocarcinoma, incidental finding
--            after cholecystectomy for presumed benign gallstone disease
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Ahmed', 'Al-Hassan', (TO_DAYS('1971-11-05') - TO_DAYS('1970-01-01')) * 86400000, 'MALE', '197111051234',
        'SYN-P0004',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p4 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p4, 'CREATE', 'Created patient: Ahmed Al-Hassan (Personal #: 197111051234)');


-- Medical history: metabolic syndrome / obesity, common gallstone risk factor
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4);
SET @p4_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p4_mh, 'CREATE', 'Created medical history for patient: Ahmed Al-Hassan with 2 diagnoses, 1 chronic condition, 0 risk factors');


INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Metabolic Syndrome / Obesity'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Obesity, unspecified'), '48', NULL),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of gallbladder'), '55', NULL);

-- Family history: mother with breast cancer (unrelated, but realistic and
-- deliberately NOT an HPB cancer, to test the AI Assistant doesn't over-fit
-- family history answers to only HPB-relevant diagnoses)
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4, (SELECT id FROM tbl_relative_type WHERE name = 'Mother'), 68);
SET @p4_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p4_fh, 'CREATE', 'Created family history entry for patient: Ahmed Al-Hassan -- Mother, died age 68 of breast cancer (non-HPB)');


-- Pathology event -> RESECTION sub-event (cholecystectomy specimen)
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Surgical resection specimen', 0, 0);
SET @p4_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-03-10')*1000,
        2, @p4,
        'Laparoscopic cholecystectomy performed for presumed symptomatic cholelithiasis. Incidental 1.8 cm mass found in the gallbladder fundus on final pathology, not appreciated on pre-operative imaging.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p4_path);
SET @p4_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p4_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Ahmed Al-Hassan');


-- No tumor_regression_system_id/value here -- this was not a neoadjuvant-
-- treated resection (incidental finding on a routine cholecystectomy), so
-- treatment-response grading genuinely doesn't apply, unlike patient 2.
INSERT INTO tbl_sub_event_resection (created_date, modified_date, created_by, modified_by, resection_type_id, organ_list_id, corporal_location_id, location_type_id, histological_tumor_type_definition_id, main_grade_of_differentiation_id, event_date, number_of_tumors, largest_tumor_diameter, satellitosis, number_of_regional_lymph_nodes_examined, number_of_regional_lymph_nodes_with_metastasis, number_of_distant_lymph_nodes_examined, number_of_distant_lymph_nodes_with_metastasis, t_parameter_id, n_parameter_id, m_parameter_id, description, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_resection_type WHERE name = 'Cholecystectomy'),
        (SELECT id FROM tbl_organ_list WHERE title = 'Gallbladder'),
        (SELECT id FROM tbl_corporal_location WHERE name = 'Gallbladder'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name = 'Gallbladder Adenocarcinoma'),
        (SELECT id FROM tbl_main_grade_of_differentiation WHERE title LIKE 'G2%'),
        UNIX_TIMESTAMP('2026-03-10')*1000, 1, 18, 0, 0, 0, 0, 0,
        (SELECT id FROM tbl_allowed_value WHERE title = 'T1a'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'N0'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'M0'),
        'Incidental gallbladder adenocarcinoma confined to the mucosa/lamina propria (pT1a), cystic duct margin negative. Given early T-stage and negative margins, no re-resection planned; surveillance imaging recommended.',
        2);
SET @p4_resection = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_path, 'PATHOLOGY', @p4_resection, 'RESECTION');
SET @p4_resection_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p4_path_root, @p4_resection_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created RESECTION sub-event for parent PATHOLOGY event');


-- SURGERY event: the operative encounter itself (the cholecystectomy was
-- originally performed for benign gallstone disease; the cancer was an
-- incidental finding on the specimen, but the operation's own record
-- still belongs here, distinct from the pathology specimen data above).
INSERT INTO tbl_event_surgery (created_date, modified_date, created_by, modified_by, operation_intent, preop_porta_venous_embolization, surgical_approach, conversion, operative_time, estimated_blood_loss, transfusion_volume, surgical_r_status, length_perop_hospital_stay, postop_readmission, postop_readmission_reason, postop_length_of_stay)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Curative', 0, 'Laparoscopic', 0, '65', '20', '0', 'R0', '0', 'No', 'N/A', '1');
SET @p4_surgery = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), UNIX_TIMESTAMP('2026-03-10')*1000,
        2, @p4,
        'Laparoscopic cholecystectomy for presumed benign gallstone disease. Uncomplicated, no conversion to open, minimal blood loss, discharged post-op day 1. Incidental gallbladder cancer identified on final pathology (see Pathology event).',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p4_surgery);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p4_surgery, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), 'Created event | Type: SURGERY | Patient: Ahmed Al-Hassan');


-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Malignant neoplasm of gallbladder'), UNIX_TIMESTAMP('2026-03-14')*1000,
        @p4, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'), 2,
        'Incidental pT1a gallbladder adenocarcinoma found on routine cholecystectomy specimen, margins negative. Early-stage, favorable prognosis; surveillance rather than further surgery per MDT.',
        0, 1, 0);
SET @p4_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p4_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Malignant neoplasm of gallbladder (incidental, pT1a, R0)');


-- Link diagnostic to its originating event (tbl_diagnostic no longer stores event_id directly as of the 2026-07-29 "diagnostic update" migration -- linkage now goes through tbl_diagnostic_event)
INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_diag, @p4_path_root);

-- Standalone Lab Test event: routine post-op bloods
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p4_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-03-24')*1000,
        2, @p4, 'Two-week post-operative bloods after incidental gallbladder cancer finding.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p4_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p4_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Two-week post-operative bloods after incidental gallbladder cancer finding');


INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_lab, (SELECT id FROM tbl_technique WHERE name = 'Automated hematology analyzer'),
  (SELECT id FROM tbl_test_name WHERE name = 'CBC – WBC'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CBC – WBC')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'cells/µL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CBC – WBC')),
  '7200', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'No evidence of infection.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4_lab, (SELECT id FROM tbl_technique WHERE name = 'Turbidimetric immunoassay'),
  (SELECT id FROM tbl_test_name WHERE name = 'CRP'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CRP')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'mg/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CRP')),
  '4', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Unremarkable, uncomplicated post-operative recovery.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '175', '96', '138/88', '76', '36.6',
        'Two-week post-cholecystectomy follow-up, unaware at surgery of the incidental gallbladder cancer finding until final pathology returned. Discussed diagnosis, staging, and surveillance plan with patient. Laparoscopic port sites healing well.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Fatigue / Asthenia / Malaise'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Surgical Oncologist / Surgeon'),
        (SELECT id FROM tbl_discipline WHERE title = 'Surgeon'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 0:%'),
        '31.3');
SET @p4_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-03-24')*1000,
        2, @p4, 'Post-cholecystectomy follow-up after incidental gallbladder cancer diagnosis.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p4_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p4_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Post-cholecystectomy follow-up after incidental gallbladder cancer diagnosis');


-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p4, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-03-24')*1000,
        '175', '96', 'Alive, early-stage (pT1a) incidental gallbladder adenocarcinoma, margins negative; on surveillance imaging rather than further surgery.', 2);
SET @p4_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p4_status, 'CREATE', 'Created status: Alive, early-stage pT1a incidental gallbladder adenocarcinoma, margins negative');



-- ============================================================================
-- PATIENT 5: Ingrid Nilsson -- Intrahepatic Cholangiocarcinoma with an
--            FGFR2 fusion (targeted-therapy candidate), biopsy-confirmed
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Ingrid', 'Nilsson', (TO_DAYS('1981-04-18') - TO_DAYS('1970-01-01')) * 86400000, 'FEMALE', '198104181234',
        'SYN-P0005',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p5 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p5, 'CREATE', 'Created patient: Ingrid Nilsson (Personal #: 198104181234)');


-- Medical history: NAFLD/MASLD background, notably younger patient (45) --
-- deliberately included to test that the AI Assistant doesn't assume HPB
-- cancers only occur in older patients.
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5);
SET @p5_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p5_mh, 'CREATE', 'Created medical history for patient: Ingrid Nilsson with 1 diagnosis, 1 chronic condition, 1 risk factor');


INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_mh, (SELECT id FROM tbl_chronic_condition WHERE name = 'Non-Alcoholic Fatty Liver Disease (NAFLD / MASLD)'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Intrahepatic bile duct carcinoma (intrahepatic cholangiocarcinoma)'), '45', NULL);

INSERT INTO tbl_medical_history_risk_factor (created_date, modified_date, created_by, modified_by, medical_history_id, risk_factor_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_mh, (SELECT id FROM tbl_risk_factor WHERE risk_factor LIKE 'Metabolic dysfunction-associated steatotic liver disease%'));

-- Family history: father died of liver cancer
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5, (SELECT id FROM tbl_relative_type WHERE name = 'Father'), 70);
SET @p5_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p5_fh, 'CREATE', 'Created family history entry for patient: Ingrid Nilsson -- Father, died age 70 of Hepatocellular carcinoma');


INSERT INTO tbl_family_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, family_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_fh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Hepatocellular carcinoma'), '67', '70');

-- Pathology event -> BIOPSY sub-event (core needle biopsy of liver mass)
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Biopsy-confirmed', 0, 0);
SET @p5_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-07-01')*1000,
        2, @p5,
        'Image-guided percutaneous core needle biopsy of a 5.5 cm segment IV/V liver mass, found incidentally on imaging for vague right-upper-quadrant discomfort. No history of cirrhosis; AFP normal, raising suspicion for cholangiocarcinoma over HCC pre-biopsy.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p5_path);
SET @p5_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p5_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Ingrid Nilsson');


INSERT INTO tbl_sub_event_biopsy (created_date, modified_date, created_by, modified_by, corporal_location_id, biopsy_type_id, location_type_id, histological_type_id, event_date, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Liver%'),
        (SELECT id FROM tbl_biopsy_type WHERE name LIKE 'Percutaneous Core Needle Biopsy%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name = 'Cholangiocarcinoma'),
        UNIX_TIMESTAMP('2026-07-01')*1000, 2);
SET @p5_biopsy = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_path, 'PATHOLOGY', @p5_biopsy, 'BIOPSY');
SET @p5_biopsy_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p5_path_root, @p5_biopsy_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created BIOPSY sub-event for parent PATHOLOGY event');


-- Molecular test (FGFR2 fusion) linked directly to the biopsy sub-event --
-- this is the key targeted-therapy-eligibility marker for iCCA
INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, sub_event_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_biopsy_link,
        (SELECT id FROM tbl_technique WHERE name = 'NGS / RNA sequencing'),
        (SELECT id FROM tbl_test_name WHERE name = 'FGFR2 fusion'),
        (SELECT id FROM tbl_test_result WHERE name = 'Fusion detected' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'FGFR2 fusion')),
        (SELECT id FROM tbl_test_unit WHERE unit = 'N/A' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'FGFR2 fusion')),
        'FGFR2-BICC1 fusion detected', 'Positive', (SELECT id FROM tbl_event_status WHERE title = 'Completed'),
        'FGFR2 fusion positive on tumor NGS -- eligible for FGFR inhibitor therapy (e.g. pemigatinib) if disease progresses on first-line chemotherapy.');

-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Intrahepatic bile duct carcinoma'), UNIX_TIMESTAMP('2026-07-05')*1000,
        @p5, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 3%'), 2,
        'Biopsy-confirmed intrahepatic cholangiocarcinoma with a positive FGFR2 fusion on tumor NGS. Locally advanced at diagnosis, not a resection candidate; starting first-line gemcitabine/cisplatin with FGFR-inhibitor therapy held in reserve for second line.',
        0, 1, 0);
SET @p5_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p5_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Intrahepatic bile duct carcinoma, FGFR2-fusion positive (biopsy-confirmed)');


-- Link diagnostic to its originating event (tbl_diagnostic no longer stores event_id directly as of the 2026-07-29 "diagnostic update" migration -- linkage now goes through tbl_diagnostic_event)
INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_diag, @p5_path_root);

-- Standalone Lab Test event: liver panel + CA 19-9
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p5_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-07-08')*1000,
        2, @p5, 'Baseline liver function and tumor marker panel prior to starting first-line chemotherapy.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p5_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p5_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Baseline liver function and tumor marker panel prior to first-line chemotherapy');


INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_lab, (SELECT id FROM tbl_technique WHERE name = 'ECLIA or ELISA'),
  (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/mL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  '156', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Elevated, consistent with cholangiocarcinoma; baseline for treatment response monitoring.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5_lab, (SELECT id FROM tbl_technique WHERE name = 'Colorimetric / Spectrophotometric'),
  (SELECT id FROM tbl_test_name WHERE name = 'ALT'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'ALT')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'ALT')),
  '32', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Preserved hepatic function, no cirrhosis background.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '168', '65', '112/70', '80', '36.9',
        'New oncology consultation to discuss chemotherapy start following biopsy-confirmed FGFR2-positive intrahepatic cholangiocarcinoma. Patient counselled on treatment plan, side effects, and future FGFR-inhibitor option if needed.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Fatigue / Asthenia / Malaise'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Medical Oncologist'),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 0:%'),
        '23.0');
SET @p5_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-07-08')*1000,
        2, @p5, 'New oncology consultation, chemotherapy treatment planning visit.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p5_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p5_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | New oncology consultation, chemotherapy treatment planning visit');


-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p5, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-07-08')*1000,
        '168', '65', 'Alive with active, locally advanced FGFR2-fusion-positive intrahepatic cholangiocarcinoma; starting first-line gemcitabine/cisplatin.', 2);
SET @p5_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p5_status, 'CREATE', 'Created status: Alive with active, locally advanced FGFR2-fusion-positive intrahepatic cholangiocarcinoma');



-- ============================================================================
-- END OF SCRIPT
-- (Pedro Paramo's notes were dropped from this script -- he no longer exists
-- after the full DB reset, and the 5 synthetic patients above already give
-- enough workflow diversity to test the AI Assistant. Not needed.)
-- ============================================================================
