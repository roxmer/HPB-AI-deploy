-- ============================================================================
-- SYNTHETIC TEST PATIENTS, BATCH 2 -- Surgery/Pathology-Resection schema
-- rebuild coverage (3 patients: SYN-P0006, SYN-P0007, SYN-P0008)
-- ============================================================================
-- Purpose: this batch is additive to synthetic_test_patients.sql (the
-- original 5 patients) and exists specifically to exercise everything added
-- by the Surgery event + Pathology-Resection rebuild (migrations
-- V1_1_117-V1_1_129; see HPB-AI_Surgery_Pathology_Resection_Changelog.md),
-- none of which the original 5-patient script could cover since it predates
-- that work. It does NOT touch, renumber, or duplicate the original 5
-- patients -- run it after them, against the same database.
--
-- Each of the 3 new patients gets a full Surgery event that goes through the
-- NEW structured fields end to end:
--   * operation_intent_id, surgical_approach_type_id, stent_definition_id,
--     surgical_r_status_id, anastomosis_technique_definition_id,
--     postoperative_complication_definition_id (all new lookup-backed FKs)
--   * operative_time_minutes, estimated_blood_loss_ml, transfusion_volume_ml,
--     length_perop_hospital_stay_days, length_icu_stay_days,
--     postop_length_of_stay_days (all new numeric fields)
--   * TWO tbl_event_surgery_resection specimen rows per Surgery (this table
--     didn't exist before this migration set)
-- and a Pathology "Resection" sub-event that:
--   * links back to that Surgery event via tbl_sub_event_resection.event_surgery_id
--   * sets tumor_regression_value_percent (patient 6 only -- see per-patient
--     notes) alongside the pre-existing free-text tumor_regression_value
--   * creates TWO tbl_resection_form rows (one per Surgery specimen, via
--     event_surgery_resection_id), each carrying its own Margin entries
--     (tbl_resection_form_margin, with the new organ_list_id + margin_value_mm)
-- plus a brand-new Sample -> Analysis -> Result chain per patient (tbl_sample
-- / tbl_analysis / tbl_analysis's molecular-report columns / tbl_result /
-- one tbl_small_variant / one tbl_copy_number_alteration row each) -- this
-- workflow has NO synthetic coverage anywhere else; the original 5 patients'
-- "molecular" data (e.g. patient 5's FGFR2 fusion) all goes through the
-- older tbl_test_form Lab Test path instead, not tbl_sample/tbl_analysis.
--
-- DELIBERATE CHOICE -- legacy free-text Surgery columns left NULL: for all
-- three Surgery events below, the old free-text columns (operation_intent,
-- surgical_approach, operative_time, estimated_blood_loss,
-- transfusion_volume, surgical_r_status, length_perop_hospital_stay,
-- postop_length_of_stay) are simply omitted from the INSERT, relying on
-- V1_1_124/V1_1_125 having relaxed every one of them to nullable. This is
-- intentional and exercises the "new Add/Edit Surgery form, which no longer
-- sends these at all" code path that V1_1_124 was written to unblock --
-- unlike the original 5-patient script (written before this rework), whose
-- two Surgery events populate ONLY the legacy columns and leave every new
-- column NULL. Between the two scripts, both the all-legacy and all-new
-- shapes of a Surgery row are now covered.
--
-- NAMING-TRAP CHECK -- every lookup name/table below was cross-checked
-- against Roxana's actual exported lookup-list content (the *_export.xlsx
-- files in deploy_HPB/HPB_Templates/), not guessed, including the two
-- naming traps the changelog calls out:
--   * tbl_event_surgery_resection (this Surgery's own specimen list) is
--     kept completely separate from tbl_resection_form/tbl_resection_form_margin
--     (this Pathology-Resection report's specimen list) -- the FK between
--     them is tbl_resection_form.event_surgery_resection_id.
--   * tbl_margin (named margins like "Parenchymal Margin") is never
--     confused with tbl_resection_margin_definition (the R0/R1/R2/Rx status
--     lookup used by tbl_event_surgery.surgical_r_status_id).
--
-- Run this against your local HPB MySQL database, after
-- synthetic_test_patients.sql, in the same way (review first, use a
-- disposable DB copy). Uses the same @app_user_id = 2 convention.
-- ============================================================================
SET @app_user_id = 2;

-- ---------------------------------------------------------------------------
-- Prerequisite seed: tbl_margin has NO migration seed data anywhere in the
-- codebase (confirmed by reading every migration touching it) -- it is only
-- ever populated by hand via the app's own Margin Excel-import screen. This
-- batch's Resection Margin data (tbl_resection_form_margin.margin_id) needs
-- it populated, so seed it here with the same 10 rows already present in
-- Margin_export.xlsx (deploy_HPB/HPB_Templates/), using the same
-- "only if currently empty" guard your own migrations use for exactly this
-- situation (see e.g. V1_1_117/118/119) -- a no-op if you've already
-- imported the real list yourself, on this DB or a future one.
-- ---------------------------------------------------------------------------
INSERT INTO tbl_margin (created_date, modified_date, title, description)
SELECT UNIX_TIMESTAMP(NOW()) * 1000, UNIX_TIMESTAMP(NOW()) * 1000, x, d
FROM (
    SELECT 'Parenchymal Margin' AS x, 'The raw surface of the liver where the surgeon cut through the functional liver tissue.' AS d
    UNION ALL SELECT 'Vascular Margin', 'The edge of a major blood vessel (like the portal vein or hepatic vein) that was dissected or reconstructed during the surgery.'
    UNION ALL SELECT 'Capsular Margin', 'The edge of a major blood vessel (like the portal vein or hepatic vein) that was dissected or reconstructed during the surgery.'
    UNION ALL SELECT 'Neck Margin (Pancreatic Transection Margin)', 'The surface where the head of the pancreas was detached from the body/tail of the pancreas.'
    UNION ALL SELECT 'Uncinate (Retroperitoneal) Margin', 'This is often considered the most critical margin. It is the deep edge where the pancreas sits against major abdominal arteries and veins.'
    UNION ALL SELECT 'Bile Duct Margin', 'The point where the common bile duct was cut to remove the diseased portion.'
    UNION ALL SELECT 'Enteric (Duodenal) Margin', 'The edges of the small intestine that are removed along with the pancreas.'
    UNION ALL SELECT 'Cystic Duct Margin', 'In a gallbladder removal (cholecystectomy) for cancer, this is the edge of the tube that connects the gallbladder to the main bile duct.'
    UNION ALL SELECT 'Liver Bed Margin', 'The area where the gallbladder was attached to the liver. In cancer cases, a "cuff" of liver tissue is often removed to ensure this margin is clear.'
    UNION ALL SELECT 'Proximal and Distal Bile Duct Margins', 'The "top" (toward the liver) and "bottom" (toward the intestine) edges of a resected bile duct segment.'
) t(x, d)
WHERE NOT EXISTS (SELECT 1 FROM tbl_margin);



-- ============================================================================
-- PATIENT 6: Lars Johansson -- Distal Cholangiocarcinoma (extrahepatic bile
--            duct), neoadjuvant chemo then Whipple resection, converted from
--            laparoscopic to open intraoperatively, R0
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Lars', 'Johansson', (TO_DAYS('1958-09-02') - TO_DAYS('1970-01-01')) * 86400000, 'MALE', '195809021234',
        'SYN-P0006',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p6 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p6, 'CREATE', 'Created patient: Lars Johansson (Personal #: 195809021234)');


-- Medical history: primary sclerosing cholangitis, the classic risk factor
-- for extrahepatic cholangiocarcinoma
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6);
SET @p6_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p6_mh, 'CREATE', 'Created medical history for patient: Lars Johansson with 1 diagnosis, 1 chronic condition, 1 risk factor');

INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_mh, (SELECT id FROM tbl_chronic_condition WHERE name LIKE 'Primary Sclerosing Cholangitis%'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of extrahepatic bile duct'), '67', NULL);

INSERT INTO tbl_medical_history_risk_factor (created_date, modified_date, created_by, modified_by, medical_history_id, risk_factor_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_mh, (SELECT id FROM tbl_risk_factor WHERE risk_factor LIKE 'Primary sclerosing cholangitis%'));

-- Family history: father, pancreatic cancer
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6, (SELECT id FROM tbl_relative_type WHERE name = 'Father'), 74);
SET @p6_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p6_fh, 'CREATE', 'Created family history entry for patient: Lars Johansson -- Father, died age 74 of pancreatic cancer');

INSERT INTO tbl_family_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, family_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_fh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of pancreatic duct'), '71', '74');


-- SURGERY event: operative encounter. See the file header for why every
-- legacy free-text column is intentionally omitted here. Created BEFORE the
-- Pathology/Resection sub-event below so event_surgery_id can be set
-- directly on that INSERT, with no forward-reference/backfill needed.
INSERT INTO tbl_event_surgery (created_date, modified_date, created_by, modified_by, operation_intent_id, preop_porta_venous_embolization, surgical_approach_type_id, conversion, stent_definition_id, operative_time_minutes, estimated_blood_loss_ml, transfusion_volume_ml, surgical_r_status_id, anastomosis_technique_definition_id, postoperative_complication_definition_id, length_perop_hospital_stay_days, length_icu_stay_days, postop_readmission, postop_readmission_reason, postop_length_of_stay_days)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_treatment_intent WHERE title = 'Curative'),
        0,
        (SELECT id FROM tbl_surgical_approach_type WHERE name = 'Open'),
        1, -- started laparoscopic-assisted, converted to open (see note)
        (SELECT id FROM tbl_stent_definition WHERE name = 'Metal'),
        430, 520, 250,
        (SELECT id FROM tbl_resection_margin_definition WHERE value LIKE 'R0%'),
        (SELECT id FROM tbl_anastomosis_technique_definition WHERE name = 'Pancreaticojejunostomy (PJ)'),
        (SELECT id FROM tbl_postoperative_complication_definition WHERE name LIKE 'Postoperative Pancreatic Fistula%'),
        1, 1, 'No', 'N/A', 11);
SET @p6_surgery = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), UNIX_TIMESTAMP('2026-04-10')*1000,
        2, @p6,
        'Pylorus-preserving pancreaticoduodenectomy after neoadjuvant gemcitabine/cisplatin for cholangiocarcinoma. Converted laparoscopic-to-open. Pancreaticojejunostomy reconstruction. Post-op: low-grade (Grade A) pancreatic fistula, managed conservatively.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p6_surgery);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p6_surgery, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), 'Created event | Type: SURGERY | Patient: Lars Johansson');


-- Surgery specimen list (tbl_event_surgery_resection) -- TWO specimens: the
-- main Whipple specimen (Pancreas) and the separately submitted distal bile
-- duct margin specimen (Bile duct). NOT the same table as the
-- tbl_resection_form rows below -- see the file header's naming-trap note.
INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Pancreas'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Pancreaticoduodenectomy (Whipple)'));
SET @p6_specimen1 = LAST_INSERT_ID();

INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Bile duct'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Extrahepatic bile duct resection'));
SET @p6_specimen2 = LAST_INSERT_ID();


-- Pathology event -> RESECTION sub-event (Whipple specimen, distal CBD
-- component). tumor_regression_value_percent is set here (alongside the
-- legacy free-text tumor_regression_value) -- this patient had neoadjuvant
-- chemo, unlike patients 7/8 below, so treatment-response grading applies.
-- Created AFTER the Surgery event above, so event_surgery_id below can
-- reference the already-set @p6_surgery directly.
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Surgical resection specimen', 1, 0);
SET @p6_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-04-10')*1000,
        2, @p6,
        'Pylorus-preserving pancreaticoduodenectomy for distal extrahepatic cholangiocarcinoma, after 3 cycles of neoadjuvant gemcitabine/cisplatin. Distal bile duct margin submitted as a separate specimen alongside the main Whipple specimen.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p6_path);
SET @p6_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p6_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Lars Johansson');

INSERT INTO tbl_sub_event_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, resection_type_id, organ_list_id, corporal_location_id, location_type_id, histological_tumor_type_definition_id, main_grade_of_differentiation_id, event_date, number_of_tumors, largest_tumor_diameter, satellitosis, number_of_regional_lymph_nodes_examined, number_of_regional_lymph_nodes_with_metastasis, number_of_distant_lymph_nodes_examined, number_of_distant_lymph_nodes_with_metastasis, tumor_regression_system_id, tumor_regression_value, tumor_regression_value_percent, t_parameter_id, n_parameter_id, m_parameter_id, description, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        @p6_surgery,
        (SELECT id FROM tbl_resection_type WHERE name = 'Pancreaticoduodenectomy (Whipple)'),
        (SELECT id FROM tbl_organ_list WHERE title = 'Pancreas'),
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Pancreas%Head%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name = 'Cholangiocarcinoma'),
        (SELECT id FROM tbl_main_grade_of_differentiation WHERE title LIKE 'G2%'),
        UNIX_TIMESTAMP('2026-04-10')*1000, 1, 28, 0, 14, 1, 0, 0,
        (SELECT id FROM tbl_tumor_regression_system WHERE title LIKE 'Grade 1%'),
        'Near-complete treatment response; rare residual tumor cells in a background of extensive fibrosis',
        90,
        (SELECT id FROM tbl_allowed_value WHERE title = 'T2'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'N1'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'M0'),
        'Pancreaticoduodenectomy for distal extrahepatic cholangiocarcinoma after neoadjuvant chemotherapy. Near-complete treatment response (CAP grade 1). All margins clear. 1/14 nodes involved.',
        2);
SET @p6_resection = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_path, 'PATHOLOGY', @p6_resection, 'RESECTION');
SET @p6_resection_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p6_path_root, @p6_resection_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created RESECTION sub-event for parent PATHOLOGY event');


-- Resection Margin Definition workflow: one tbl_resection_form row per
-- Surgery specimen, each linked via event_surgery_resection_id, each with
-- its own Margin entries.
INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Pancreaticoduodenectomy (Whipple)'),
        @p6_specimen1);
SET @p6_form1 = LAST_INSERT_ID();

INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Extrahepatic bile duct resection'),
        @p6_specimen2);
SET @p6_form2 = LAST_INSERT_ID();

INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_form1,
  (SELECT id FROM tbl_margin WHERE title LIKE 'Neck Margin%'), 'Clear, 3 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Pancreas'), 3),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_form1,
  (SELECT id FROM tbl_margin WHERE title LIKE 'Uncinate%'), 'Clear but close, 1 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Pancreas'), 1);

INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_form2,
  (SELECT id FROM tbl_margin WHERE title = 'Bile Duct Margin'), 'Clear, 4 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Bile duct'), 4),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_form2,
  (SELECT id FROM tbl_margin WHERE title LIKE 'Proximal and Distal Bile Duct%'), 'Clear, 2 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Bile duct'), 2);


-- Sample -> Analysis -> Result: targeted NGS panel on the resected tumor
-- tissue, sample linked to the Pathology root event it was taken from.
INSERT INTO tbl_sample (created_date, modified_date, created_by, modified_by, event_id, patient_id, sample_type_id, sample_date, extraction_method_id, quality_value, sampleID)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_path_root, @p6,
        (SELECT id FROM tbl_sample_type WHERE type_name = 'Solid tumour tissue'),
        UNIX_TIMESTAMP('2026-04-13')*1000,
        (SELECT id FROM tbl_extraction_method WHERE title = 'FFPE Extraction'),
        'Sufficient tumor content, ~40% cellularity',
        'SYN-P0006-S1');
SET @p6_sample = LAST_INSERT_ID();
INSERT INTO tbl_sample_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'SAMPLE', @p6_sample, 'CREATE', 'SAMPLE | CREATED | Patient: Lars Johansson, Sample Type: Solid tumour tissue, Event: PATHOLOGY, Date: 2026-04-13');

INSERT INTO tbl_analysis (created_date, modified_date, created_by, modified_by, analysis_type_id, sample_id, description, issued_by_lab, note, analysis_status_id, external_reference, report_date, received_date, source_document_path, summary_text)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_analysis_type WHERE name = 'Targeted Sequencing'),
        @p6_sample,
        'Targeted NGS panel (biliary/pancreatic driver gene panel) on resected tumor tissue',
        'Karolinska Genomic Medicine Center, Stockholm',
        'Requested to guide adjuvant treatment selection given neoadjuvant response.',
        (SELECT id FROM tbl_analysis_status WHERE name = 'REVIEWED'),
        'KGMC-2026-04871',
        UNIX_TIMESTAMP('2026-04-29')*1000, UNIX_TIMESTAMP('2026-04-14')*1000,
        '/reports/molecular/SYN-P0006_targeted_panel_report.pdf',
        'KRAS G12D pathogenic hotspot mutation detected. Concurrent CDKN2A copy number loss. Tumor mutational burden low. No actionable fusion detected.');
SET @p6_analysis = LAST_INSERT_ID();

INSERT INTO tbl_small_variant (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, consequence, clonality_zygosity, assessment, transcript_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_analysis, 'KRAS', 'Targeted NGS panel', 'c.35G>A (p.G12D)', 'Missense', 'Heterozygous, clonal', 'Pathogenic', 'NM_004985');

INSERT INTO tbl_copy_number_alteration (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, assessment, copy_number)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_analysis, 'CDKN2A', 'Targeted NGS panel', 'Homozygous deletion, chr9p21.3', 'Likely pathogenic', '0');

INSERT INTO tbl_result (created_date, modified_date, created_by, modified_by, analysis_id, result_type_id, result_value, result_name, result_name_id, unit, comment)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_analysis, NULL, '38', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Fraction Of Cancer Dna'), '%', 'Tumor purity/cellularity estimate from panel data.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_analysis, NULL, 'Low (2.1 mut/Mb)', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Tumor Mutational Burden'), 'mut/Mb', NULL),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_analysis,
  (SELECT id FROM tbl_result_type WHERE name = 'Positive'), 'KRAS G12D pathogenic variant detected', 'KRAS G12D', NULL, NULL,
  'Consistent with a pancreatobiliary-type ductal adenocarcinoma driver profile.');


-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Malignant neoplasm of extrahepatic bile duct'), UNIX_TIMESTAMP('2026-04-16')*1000,
        @p6, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 2%'), 2,
        'ypT2N1, R0-resected distal extrahepatic cholangiocarcinoma after neoadjuvant chemo and Whipple resection; near-complete treatment response. Adjuvant chemo planned per MDT. KRAS G12D detected on tumor NGS, no targetable fusion.',
        0, 1, 0);
SET @p6_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p6_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Malignant neoplasm of extrahepatic bile duct (Whipple resection, ypT2N1 R0)');

INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_diag, @p6_path_root);

-- Standalone Lab Test event: routine post-op bloods + tumor marker
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p6_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-05-08')*1000,
        2, @p6, 'Four-week post-Whipple follow-up bloods, prior to starting adjuvant chemotherapy.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p6_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p6_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Four-week post-Whipple follow-up bloods');

INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6_lab, (SELECT id FROM tbl_technique WHERE name = 'ECLIA or ELISA'),
  (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9'),
  (SELECT id FROM tbl_test_result WHERE name = 'Normal' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/mL' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CA 19-9')),
  '22', NULL, (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Normalized post-resection.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '176', '78', '128/80', '74', '36.7',
        'Four-week post-operative surgical follow-up after converted-to-open Whipple resection. Drain output from the low-grade pancreatic fistula has resolved; wound healing well. Cleared to proceed with adjuvant chemotherapy.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Abdominal Pain'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Surgical Oncologist / Surgeon'),
        (SELECT id FROM tbl_discipline WHERE title = 'Surgeon'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '25.2');
SET @p6_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-05-08')*1000,
        2, @p6, 'Four-week post-Whipple surgical follow-up.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p6_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p6_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Four-week post-Whipple surgical follow-up');

-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p6, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-05-08')*1000,
        '176', '78', 'Alive, R0-resected distal extrahepatic cholangiocarcinoma (ypT2N1) status post neoadjuvant chemotherapy and Whipple resection; recovering well, about to start adjuvant chemotherapy.', 2);
SET @p6_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p6_status, 'CREATE', 'Created status: Alive, R0-resected distal CCA status post Whipple resection');



-- ============================================================================
-- PATIENT 7: Birgitta Holm -- Recurrent Hepatocellular Carcinoma (HCC) on a
--            background of viral hepatitis-related cirrhosis, robotic
--            extended right hepatectomy with preoperative portal vein
--            embolization, R1 (positive margin)
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Birgitta', 'Holm', (TO_DAYS('1955-12-20') - TO_DAYS('1970-01-01')) * 86400000, 'FEMALE', '195512201234',
        'SYN-P0007',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p7 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p7, 'CREATE', 'Created patient: Birgitta Holm (Personal #: 195512201234)');


-- Medical history: chronic viral hepatitis + cirrhosis, the classic HCC
-- background, plus a prior HCC diagnosis (this Surgery is for recurrence)
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7);
SET @p7_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p7_mh, 'CREATE', 'Created medical history for patient: Birgitta Holm with 1 diagnosis, 2 chronic conditions, 1 risk factor');

INSERT INTO tbl_medical_history_chronic_condition (created_date, modified_date, created_by, modified_by, medical_history_id, chronic_condition_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_mh, (SELECT id FROM tbl_chronic_condition WHERE name LIKE 'Chronic Viral Hepatitis%')),
       (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_mh, (SELECT id FROM tbl_chronic_condition WHERE name LIKE 'Cirrhosis%'));

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Hepatocellular carcinoma'), '68', NULL);

INSERT INTO tbl_medical_history_risk_factor (created_date, modified_date, created_by, modified_by, medical_history_id, risk_factor_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_mh, (SELECT id FROM tbl_risk_factor WHERE risk_factor LIKE 'Chronic hepatitis B infection%'));

-- Family history: mother, liver cancer
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7, (SELECT id FROM tbl_relative_type WHERE name = 'Mother'), 66);
SET @p7_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p7_fh, 'CREATE', 'Created family history entry for patient: Birgitta Holm -- Mother, died age 66 of liver cancer');

INSERT INTO tbl_family_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, family_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_fh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Hepatocellular carcinoma'), '63', '66');


-- SURGERY event: preop_porta_venous_embolization = 1 here (deliberately
-- different from every Surgery row in the original 5-patient script, which
-- always used 0) -- portal vein embolization ahead of a major hepatectomy on
-- a cirrhotic liver is standard practice and worth having covered. Created
-- BEFORE the Pathology/Resection sub-event below so event_surgery_id can be
-- set directly on that INSERT, with no forward-reference/backfill needed.
INSERT INTO tbl_event_surgery (created_date, modified_date, created_by, modified_by, operation_intent_id, preop_porta_venous_embolization, surgical_approach_type_id, conversion, stent_definition_id, operative_time_minutes, estimated_blood_loss_ml, transfusion_volume_ml, surgical_r_status_id, anastomosis_technique_definition_id, postoperative_complication_definition_id, length_perop_hospital_stay_days, length_icu_stay_days, postop_readmission, postop_readmission_reason, postop_length_of_stay_days)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_treatment_intent WHERE title = 'Curative'),
        1,
        (SELECT id FROM tbl_surgical_approach_type WHERE name = 'Robotic'),
        0,
        (SELECT id FROM tbl_stent_definition WHERE name = 'None'),
        340, 300, 0,
        (SELECT id FROM tbl_resection_margin_definition WHERE value LIKE 'R1%'),
        NULL, -- no anastomosis for a straight hepatectomy -- deliberately NULL
        NULL, -- no post-operative complication recorded -- deliberately NULL
        0, 2, 'No', 'N/A', 6);
SET @p7_surgery = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), UNIX_TIMESTAMP('2026-06-15')*1000,
        2, @p7,
        'Robotic extended right hepatectomy for recurrent HCC on cirrhotic liver, after preop right portal vein embolization. Segment IVb satellite nodule resected same operation. Two-night ICU stay; no transfusion. Final margin R1 (microscopically positive).',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p7_surgery);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p7_surgery, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), 'Created event | Type: SURGERY | Patient: Birgitta Holm');


-- Surgery specimen list -- TWO specimens, both Liver: the main extended
-- hepatectomy specimen and the separate segment IVb satellite nodule.
INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Liver'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended hepatectomy'));
SET @p7_specimen1 = LAST_INSERT_ID();

INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Liver'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Partial / Segmental hepatectomy'));
SET @p7_specimen2 = LAST_INSERT_ID();


-- Pathology event -> RESECTION sub-event (recurrent HCC, no neoadjuvant
-- treatment for this upfront resection -- tumor_regression fields
-- intentionally left NULL, same reasoning as patient 4 in the original
-- 5-patient script). Created AFTER the Surgery event above, so
-- event_surgery_id below can reference the already-set @p7_surgery directly.
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Surgical resection specimen', 0, 1);
SET @p7_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-06-15')*1000,
        2, @p7,
        'Robotic extended right hepatectomy for recurrent HCC, 3 years after initial partial hepatectomy, on a background of HBV-related cirrhosis. A second small satellite nodule in segment IVb was resected separately in the same operation.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p7_path);
SET @p7_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p7_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Birgitta Holm');

INSERT INTO tbl_sub_event_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, resection_type_id, organ_list_id, corporal_location_id, location_type_id, histological_tumor_type_definition_id, main_grade_of_differentiation_id, event_date, number_of_tumors, largest_tumor_diameter, satellitosis, number_of_regional_lymph_nodes_examined, number_of_regional_lymph_nodes_with_metastasis, number_of_distant_lymph_nodes_examined, number_of_distant_lymph_nodes_with_metastasis, t_parameter_id, n_parameter_id, m_parameter_id, description, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        @p7_surgery,
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended hepatectomy'),
        (SELECT id FROM tbl_organ_list WHERE title = 'Liver'),
        (SELECT id FROM tbl_corporal_location WHERE name LIKE 'Liver%'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name = 'Hepatocellular Carcinoma (HCC)'),
        (SELECT id FROM tbl_main_grade_of_differentiation WHERE title LIKE 'G2%'),
        UNIX_TIMESTAMP('2026-06-15')*1000, 2, 41, 1, 0, 0, 0, 0,
        (SELECT id FROM tbl_allowed_value WHERE title = 'T3'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'N0'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'M0'),
        'Recurrent HCC, extended right hepatectomy with a separate satellite nodule from segment IVb (2 tumors total, satellitosis present). Parenchymal transection margin involved microscopically (R1) -- see Surgery event for structured margin status.',
        2);
SET @p7_resection = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_path, 'PATHOLOGY', @p7_resection, 'RESECTION');
SET @p7_resection_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p7_path_root, @p7_resection_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created RESECTION sub-event for parent PATHOLOGY event');


INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended hepatectomy'),
        @p7_specimen1);
SET @p7_form1 = LAST_INSERT_ID();

INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Partial / Segmental hepatectomy'),
        @p7_specimen2);
SET @p7_form2 = LAST_INSERT_ID();

-- Margins on the main specimen: parenchymal margin involved (0 mm -- this
-- is the R1 margin referenced from the Surgery event above), vascular
-- margin clear.
INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_form1,
  (SELECT id FROM tbl_margin WHERE title = 'Parenchymal Margin'), 'Involved, tumor at margin (0 mm)',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 0),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_form1,
  (SELECT id FROM tbl_margin WHERE title = 'Vascular Margin'), 'Clear, 5 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 5);

-- Margins on the second (satellite nodule) specimen: both clear.
INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_form2,
  (SELECT id FROM tbl_margin WHERE title = 'Parenchymal Margin'), 'Clear, 6 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 6),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_form2,
  (SELECT id FROM tbl_margin WHERE title = 'Capsular Margin'), 'Clear, 4 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 4);


-- Sample -> Analysis -> Result: tumor NGS (whole-exome) on the resected HCC
-- tissue.
INSERT INTO tbl_sample (created_date, modified_date, created_by, modified_by, event_id, patient_id, sample_type_id, sample_date, extraction_method_id, quality_value, sampleID)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_path_root, @p7,
        (SELECT id FROM tbl_sample_type WHERE type_name = 'Solid tumour tissue'),
        UNIX_TIMESTAMP('2026-06-18')*1000,
        (SELECT id FROM tbl_extraction_method WHERE title = 'FFPE Extraction'),
        'Sufficient tumor content, ~55% cellularity',
        'SYN-P0007-S1');
SET @p7_sample = LAST_INSERT_ID();
INSERT INTO tbl_sample_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'SAMPLE', @p7_sample, 'CREATE', 'SAMPLE | CREATED | Patient: Birgitta Holm, Sample Type: Solid tumour tissue, Event: PATHOLOGY, Date: 2026-06-18');

INSERT INTO tbl_analysis (created_date, modified_date, created_by, modified_by, analysis_type_id, sample_id, description, issued_by_lab, note, analysis_status_id, external_reference, report_date, received_date, source_document_path, summary_text)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_analysis_type WHERE name = 'Whole-Exome Sequencing (WES)'),
        @p7_sample,
        'Tumor whole-exome sequencing on resected recurrent HCC tissue',
        'Karolinska Genomic Medicine Center, Stockholm',
        'Requested given R1 margin and cirrhotic background, to assess recurrence risk profile and any actionable findings.',
        (SELECT id FROM tbl_analysis_status WHERE name = 'REVIEWED'),
        'KGMC-2026-06215',
        UNIX_TIMESTAMP('2026-07-06')*1000, UNIX_TIMESTAMP('2026-06-19')*1000,
        '/reports/molecular/SYN-P0007_WES_report.pdf',
        'TP53 pathogenic hotspot mutation detected. Concurrent CCND1 amplification. Microsatellite stable. No actionable fusion detected.');
SET @p7_analysis = LAST_INSERT_ID();

INSERT INTO tbl_small_variant (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, consequence, clonality_zygosity, assessment, transcript_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_analysis, 'TP53', 'Whole-exome sequencing', 'c.745C>A (p.R249S)', 'Missense', 'Heterozygous, clonal', 'Pathogenic', 'NM_000546');

INSERT INTO tbl_copy_number_alteration (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, assessment, copy_number)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_analysis, 'CCND1', 'Whole-exome sequencing', 'Amplification, chr11q13.3', 'Likely pathogenic', '8');

INSERT INTO tbl_result (created_date, modified_date, created_by, modified_by, analysis_id, result_type_id, result_value, result_name, result_name_id, unit, comment)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_analysis, NULL, '45', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Fraction Of Cancer Dna'), '%', 'Tumor purity/cellularity estimate from WES data.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_analysis,
  (SELECT id FROM tbl_result_type WHERE name = 'Negative'), 'MSS (Stable)', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Msi Status'), NULL, NULL),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_analysis,
  (SELECT id FROM tbl_result_type WHERE name = 'Positive'), 'TP53 pathogenic variant (R249S) detected', 'TP53 R249S', NULL, NULL,
  'Given R1 margin, discuss adjuvant options and close surveillance imaging interval at MDT.');


-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Liver cell carcinoma'), UNIX_TIMESTAMP('2026-06-19')*1000,
        @p7, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 3%'), 2,
        'Recurrent HCC (pT3N0), extended right hepatectomy + segment IVb nodule resection after portal vein embolization. R1 margin on final pathology. TP53-mutant, CCND1-amplified. Close surveillance; adjuvant therapy under MDT discussion given R1 status.',
        1, 1, 0);
SET @p7_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p7_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Recurrent hepatocellular carcinoma (extended hepatectomy, pT3N0 R1)');

INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_diag, @p7_path_root);

-- Standalone Lab Test event: liver panel (important post-hepatectomy on a
-- cirrhotic liver) + tumor marker
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p7_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-07-01')*1000,
        2, @p7, 'Two-week post-hepatectomy liver function panel, given cirrhotic background and extent of resection.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p7_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p7_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Two-week post-hepatectomy liver function panel');

INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7_lab, (SELECT id FROM tbl_technique WHERE name = 'Colorimetric / Spectrophotometric'),
  (SELECT id FROM tbl_test_name WHERE name = 'ALT'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'ALT')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'U/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'ALT')),
  '68', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Mildly elevated, expected post-hepatectomy regeneration on a cirrhotic liver; trending down.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '162', '68', '124/78', '78', '36.8',
        'Two-week post-hepatectomy surgical follow-up. Liver regenerating appropriately, mild transaminitis trending down. Discussed R1 margin finding and adjuvant/surveillance options.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 1%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Fatigue / Asthenia / Malaise'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Surgical Oncologist / Surgeon'),
        (SELECT id FROM tbl_discipline WHERE title = 'Surgeon'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '25.9');
SET @p7_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-07-01')*1000,
        2, @p7, 'Two-week post-hepatectomy surgical follow-up.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p7_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p7_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Two-week post-hepatectomy surgical follow-up');

-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p7, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-07-01')*1000,
        '162', '68', 'Alive with recurrent HCC (pT3N0, R1) status post extended right hepatectomy on a cirrhotic liver; close imaging surveillance, adjuvant therapy under discussion.', 2);
SET @p7_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p7_status, 'CREATE', 'Created status: Alive with recurrent HCC, R1-resected, close surveillance');



-- ============================================================================
-- PATIENT 8: Yusuf Abdi -- Locally advanced Gallbladder Adenocarcinoma with
--            direct liver invasion, preoperative biliary stent for
--            obstructive jaundice, open extended cholecystectomy + central
--            hepatectomy with palliative intent, R2 (macroscopic residual)
-- ============================================================================
INSERT INTO tbl_patient (created_date, modified_date, created_by, modified_by, first_name, last_name, date_of_birth, sex, personal_number, patientID, organization_id, discipline_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Yusuf', 'Abdi', (TO_DAYS('1968-06-11') - TO_DAYS('1970-01-01')) * 86400000, 'MALE', '196806111234',
        'SYN-P0008',
        (SELECT id FROM tbl_organization WHERE name = 'Karolinska' LIMIT 1),
        (SELECT id FROM tbl_discipline WHERE title = 'Oncologist' LIMIT 1));
SET @p8 = LAST_INSERT_ID();
INSERT INTO tbl_patient_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'PATIENT', @p8, 'CREATE', 'Created patient: Yusuf Abdi (Personal #: 196806111234)');


-- Medical history: longstanding gallstone disease, a well-established
-- gallbladder cancer risk factor
INSERT INTO tbl_medical_history (created_date, modified_date, created_by, modified_by, patient_id) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8);
SET @p8_mh = LAST_INSERT_ID();
INSERT INTO tbl_medical_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'MEDICAL_HISTORY', @p8_mh, 'CREATE', 'Created medical history for patient: Yusuf Abdi with 1 diagnosis, 0 chronic conditions, 1 risk factor');

INSERT INTO tbl_medical_history_clinical_diagnosis (created_date, modified_date, created_by, modified_by, medical_history_id, clinical_diagnosis_id, age_noted, age_ceased)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_mh, (SELECT id FROM tbl_clinical_diagnosis WHERE name = 'Malignant neoplasm of gallbladder'), '57', NULL);

INSERT INTO tbl_medical_history_risk_factor (created_date, modified_date, created_by, modified_by, medical_history_id, risk_factor_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_mh, (SELECT id FROM tbl_risk_factor WHERE risk_factor LIKE 'Gallstones (cholelithiasis)%'));

-- Family history: brother (father's side), colorectal cancer -- deliberately
-- not an HPB cancer, same rationale as patient 4 in the original script
INSERT INTO tbl_family_history (created_date, modified_date, created_by, modified_by, patient_id, relative_type_id, age_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8, (SELECT id FROM tbl_relative_type WHERE name LIKE 'Brother%father%'), 62);
SET @p8_fh = LAST_INSERT_ID();
INSERT INTO tbl_family_history_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'FAMILY_HISTORY', @p8_fh, 'CREATE', 'Created family history entry for patient: Yusuf Abdi -- Brother, died age 62 of colorectal cancer (non-HPB)');


-- SURGERY event: operation_intent_id = 'Palliative' here -- deliberately
-- different from every other Surgery in both this batch and the original
-- 5-patient script, which are all 'Curative'. Surgery started with curative
-- intent but was converted to a palliative debulking goal intraoperatively
-- once the extent of liver invasion became apparent (reflected in the R2
-- outcome, not a change to the recorded plan). Created BEFORE the
-- Pathology/Resection sub-event below so event_surgery_id can be set
-- directly on that INSERT, with no forward-reference/backfill needed.
INSERT INTO tbl_event_surgery (created_date, modified_date, created_by, modified_by, operation_intent_id, preop_porta_venous_embolization, surgical_approach_type_id, conversion, stent_definition_id, operative_time_minutes, estimated_blood_loss_ml, transfusion_volume_ml, surgical_r_status_id, anastomosis_technique_definition_id, postoperative_complication_definition_id, length_perop_hospital_stay_days, length_icu_stay_days, postop_readmission, postop_readmission_reason, postop_length_of_stay_days)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_treatment_intent WHERE title = 'Palliative'),
        0,
        (SELECT id FROM tbl_surgical_approach_type WHERE name = 'Open'),
        0,
        (SELECT id FROM tbl_stent_definition WHERE name = 'Plastic'),
        280, 650, 300,
        (SELECT id FROM tbl_resection_margin_definition WHERE value LIKE 'R2%'),
        (SELECT id FROM tbl_anastomosis_technique_definition WHERE name = 'Hepaticojejunostomy'),
        (SELECT id FROM tbl_postoperative_complication_definition WHERE name = 'Bile Leak'),
        1, 1, 'Yes', 'Readmitted on postop day 6 for a symptomatic bile leak, managed with percutaneous drainage.', 9);
SET @p8_surgery = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), UNIX_TIMESTAMP('2026-02-20')*1000,
        2, @p8,
        'Open extended cholecystectomy + central hepatectomy with HJ reconstruction for gallbladder cancer with hepatic invasion. Invasion exceeded imaging; macroscopic residual (R2), debulking. Post-op bile leak, readmitted, percutaneous drainage.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p8_surgery);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p8_surgery, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'SURGERY'), 'Created event | Type: SURGERY | Patient: Yusuf Abdi');


-- Surgery specimen list -- TWO specimens: the gallbladder/cystic-duct
-- specimen and the separate central hepatectomy liver specimen.
INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Gallbladder'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended cholecystectomy'));
SET @p8_specimen1 = LAST_INSERT_ID();

INSERT INTO tbl_event_surgery_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, organ_list_id, resection_type_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_surgery,
        (SELECT id FROM tbl_organ_list WHERE title = 'Liver'),
        (SELECT id FROM tbl_resection_type WHERE name = 'Central hepatectomy'));
SET @p8_specimen2 = LAST_INSERT_ID();


-- Pathology event -> RESECTION sub-event (locally advanced gallbladder
-- cancer with direct liver invasion; no neoadjuvant treatment -- upfront
-- surgery -- tumor_regression fields left NULL, same as patient 4 and
-- patient 7 above). Created AFTER the Surgery event above, so
-- event_surgery_id below can reference the already-set @p8_surgery directly.
INSERT INTO tbl_event_pathology (created_date, modified_date, created_by, modified_by, pathology_type, had_neoadjuvant_treatment, is_recurrent)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'Surgical resection specimen', 0, 0);
SET @p8_path = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), UNIX_TIMESTAMP('2026-02-20')*1000,
        2, @p8,
        'Extended cholecystectomy with central (segment IVb/V) hepatectomy for locally advanced gallbladder adenocarcinoma with direct liver invasion, more extensive intraoperatively than imaging suggested. Specimens submitted separately.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p8_path);
SET @p8_path_root = LAST_INSERT_ID();
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p8_path, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'Created event | Type: PATHOLOGY | Patient: Yusuf Abdi');

INSERT INTO tbl_sub_event_resection (created_date, modified_date, created_by, modified_by, event_surgery_id, resection_type_id, organ_list_id, corporal_location_id, location_type_id, histological_tumor_type_definition_id, main_grade_of_differentiation_id, event_date, number_of_tumors, largest_tumor_diameter, satellitosis, number_of_regional_lymph_nodes_examined, number_of_regional_lymph_nodes_with_metastasis, number_of_distant_lymph_nodes_examined, number_of_distant_lymph_nodes_with_metastasis, t_parameter_id, n_parameter_id, m_parameter_id, description, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        @p8_surgery,
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended cholecystectomy'),
        (SELECT id FROM tbl_organ_list WHERE title = 'Gallbladder'),
        (SELECT id FROM tbl_corporal_location WHERE name = 'Gallbladder'),
        (SELECT id FROM tbl_location_type WHERE name = 'Primary Tumor'),
        (SELECT id FROM tbl_histological_tumor_type_definition WHERE name = 'Gallbladder Adenocarcinoma'),
        (SELECT id FROM tbl_main_grade_of_differentiation WHERE title LIKE 'G3%'),
        UNIX_TIMESTAMP('2026-02-20')*1000, 1, 52, 0, 9, 3, 0, 0,
        (SELECT id FROM tbl_allowed_value WHERE title = 'T4'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'N1'),
        (SELECT id FROM tbl_allowed_value WHERE title = 'M0'),
        'Locally advanced gallbladder adenocarcinoma with direct hepatic invasion (pT4). 3/9 regional nodes involved. Residual disease at the liver bed given extent of invasion -- macroscopic residual tumor (R2), see Surgery event for structured margin status.',
        2);
SET @p8_resection = LAST_INSERT_ID();

INSERT INTO tbl_event_sub_event (created_date, modified_date, created_by, modified_by, parent_event_id, event_type, sub_event_id, sub_event_type)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_path, 'PATHOLOGY', @p8_resection, 'RESECTION');
SET @p8_resection_link = LAST_INSERT_ID();
INSERT INTO tbl_sub_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, sub_event_id, event_type_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p8_path_root, @p8_resection_link, (SELECT id FROM tbl_event_type WHERE event_name = 'PATHOLOGY'), 'CREATE', 'Created RESECTION sub-event for parent PATHOLOGY event');


INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Extended cholecystectomy'),
        @p8_specimen1);
SET @p8_form1 = LAST_INSERT_ID();

INSERT INTO tbl_resection_form (created_date, modified_date, created_by, modified_by, sub_event_resection_id, resection_type_id, event_surgery_resection_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_resection,
        (SELECT id FROM tbl_resection_type WHERE name = 'Central hepatectomy'),
        @p8_specimen2);
SET @p8_form2 = LAST_INSERT_ID();

-- Margins on the gallbladder specimen: cystic duct margin involved.
INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_form1,
  (SELECT id FROM tbl_margin WHERE title = 'Cystic Duct Margin'), 'Involved, tumor at margin (0 mm)',
  (SELECT id FROM tbl_organ_list WHERE title = 'Gallbladder'), 0),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_form1,
  (SELECT id FROM tbl_margin WHERE title = 'Liver Bed Margin'), 'Involved, macroscopic residual disease (0 mm)',
  (SELECT id FROM tbl_organ_list WHERE title = 'Gallbladder'), 0);

-- Margins on the liver specimen: both clear (the macroscopic residual
-- disease was left AT the liver bed rather than within this resected
-- specimen itself -- a realistic, if slightly unusual, R2 pattern).
INSERT INTO tbl_resection_form_margin (created_date, modified_date, created_by, modified_by, resection_form_id, margin_id, margin_type_value, organ_list_id, margin_value_mm)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_form2,
  (SELECT id FROM tbl_margin WHERE title = 'Parenchymal Margin'), 'Clear, 2 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 2),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_form2,
  (SELECT id FROM tbl_margin WHERE title = 'Vascular Margin'), 'Clear but close, 1 mm',
  (SELECT id FROM tbl_organ_list WHERE title = 'Liver'), 1);


-- Sample -> Analysis -> Result: targeted panel on the gallbladder specimen,
-- looking for HER2 alterations (an established gallbladder-cancer
-- targeted-therapy angle, mirroring patient 5's FGFR2 story in the
-- original 5-patient script).
INSERT INTO tbl_sample (created_date, modified_date, created_by, modified_by, event_id, patient_id, sample_type_id, sample_date, extraction_method_id, quality_value, sampleID)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_path_root, @p8,
        (SELECT id FROM tbl_sample_type WHERE type_name = 'Solid tumour tissue'),
        UNIX_TIMESTAMP('2026-02-24')*1000,
        (SELECT id FROM tbl_extraction_method WHERE title = 'FFPE Extraction'),
        'Sufficient tumor content, ~48% cellularity',
        'SYN-P0008-S1');
SET @p8_sample = LAST_INSERT_ID();
INSERT INTO tbl_sample_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'SAMPLE', @p8_sample, 'CREATE', 'SAMPLE | CREATED | Patient: Yusuf Abdi, Sample Type: Solid tumour tissue, Event: PATHOLOGY, Date: 2026-02-24');

INSERT INTO tbl_analysis (created_date, modified_date, created_by, modified_by, analysis_type_id, sample_id, description, issued_by_lab, note, analysis_status_id, external_reference, report_date, received_date, source_document_path, summary_text)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id,
        (SELECT id FROM tbl_analysis_type WHERE name = 'Targeted Sequencing'),
        @p8_sample,
        'Targeted NGS panel (biliary tract gene panel, including ERBB2/HER2) on resected gallbladder tumor tissue',
        'Karolinska Genomic Medicine Center, Stockholm',
        'Requested given R2 (macroscopic residual) status to identify targeted-therapy options for residual/recurrent disease.',
        (SELECT id FROM tbl_analysis_status WHERE name = 'REVIEWED'),
        'KGMC-2026-02998',
        UNIX_TIMESTAMP('2026-03-12')*1000, UNIX_TIMESTAMP('2026-02-25')*1000,
        '/reports/molecular/SYN-P0008_targeted_panel_report.pdf',
        'ERBB2 (HER2) activating mutation detected, concordant with ERBB2 amplification. Intermediate tumor mutational burden. No actionable fusion detected.');
SET @p8_analysis = LAST_INSERT_ID();

INSERT INTO tbl_small_variant (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, consequence, clonality_zygosity, assessment, transcript_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_analysis, 'ERBB2', 'Targeted NGS panel', 'c.929C>T (p.S310F)', 'Missense', 'Heterozygous, clonal', 'Pathogenic', 'NM_004448');

INSERT INTO tbl_copy_number_alteration (created_date, modified_date, created_by, modified_by, analysis_id, gene, source, variant_details, assessment, copy_number)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_analysis, 'ERBB2', 'Targeted NGS panel', 'Amplification, chr17q12', 'Pathogenic', '12');

INSERT INTO tbl_result (created_date, modified_date, created_by, modified_by, analysis_id, result_type_id, result_value, result_name, result_name_id, unit, comment)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_analysis, NULL, '52', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Fraction Of Cancer Dna'), '%', 'Tumor purity/cellularity estimate from panel data.'),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_analysis, NULL, 'Intermediate (6.4 mut/Mb)', NULL,
  (SELECT id FROM tbl_result_name WHERE name = 'Tumor Mutational Burden'), 'mut/Mb', NULL),
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_analysis,
  (SELECT id FROM tbl_result_type WHERE name = 'Positive'), 'ERBB2 (HER2) activating mutation and amplification detected', 'ERBB2 S310F + amplification', NULL, NULL,
  'Concordant HER2 mutation and amplification -- candidate for HER2-directed therapy given macroscopic residual (R2) disease; discuss at MDT.');


-- Diagnostic record anchored to the pathology event
INSERT INTO tbl_diagnostic (created_date, modified_date, created_by, modified_by, diagnostic_type_id, diagnostic_date, patient_id, severity_type_id, responsible_user_id, note, is_chronic, is_active, is_cause_of_death)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_diagnostic_type WHERE name = 'Malignant neoplasm of gallbladder'), UNIX_TIMESTAMP('2026-02-25')*1000,
        @p8, (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 3%'), 2,
        'Locally advanced gallbladder adenocarcinoma (pT4N1) with hepatic invasion. Extended cholecystectomy + central hepatectomy: macroscopic residual (R2), palliative debulking. ERBB2 (HER2) mutation/amplification on NGS; HER2-directed therapy planned.',
        0, 1, 0);
SET @p8_diag = LAST_INSERT_ID();
INSERT INTO tbl_diagnostic_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'DIAGNOSTIC', @p8_diag, 'CREATE', 'DIAGNOSTIC | CREATED | Locally advanced gallbladder adenocarcinoma (pT4N1, R2, HER2-positive)');

INSERT INTO tbl_diagnostic_event (created_date, modified_date, created_by, modified_by, diagnostic_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_diag, @p8_path_root);

-- Standalone Lab Test event: post-readmission bloods after the bile leak
INSERT INTO tbl_event_lab_test (created_date, modified_date, created_by, modified_by) VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id);
SET @p8_lab = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), UNIX_TIMESTAMP('2026-03-05')*1000,
        2, @p8, 'Bloods following percutaneous drainage of the post-operative bile leak.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p8_lab);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p8_lab, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'LAB TEST'), 'Created event | Type: LAB TEST | Bloods following bile leak drainage');

INSERT INTO tbl_test_form (created_date, modified_date, created_by, modified_by, lab_test_id, technique_id, test_name_id, test_result_id, test_unit_id, value, flag, event_status_id, lab_result)
VALUES
 (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8_lab, (SELECT id FROM tbl_technique WHERE name = 'Turbidimetric immunoassay'),
  (SELECT id FROM tbl_test_name WHERE name = 'CRP'),
  (SELECT id FROM tbl_test_result WHERE name = 'Elevated' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CRP')),
  (SELECT id FROM tbl_test_unit WHERE unit = 'mg/L' AND test_name_id = (SELECT id FROM tbl_test_name WHERE name = 'CRP')),
  '86', 'H', (SELECT id FROM tbl_event_status WHERE title = 'Completed'), 'Elevated, consistent with the bile leak; trending down after percutaneous drainage.');

-- Medical Assessment event
INSERT INTO tbl_event_medical_assessment (created_date, modified_date, created_by, modified_by, is_referral, height, weight, blood_pressure, heart_rate, temperature, note, severity_id, adverse_reaction_id, consultation_type_id, discipline_id, grade_id, bmi)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 0, '174', '81', '118/76', '84', '37.1',
        'Follow-up after percutaneous drainage of a post-operative bile leak. Drain output decreasing, afebrile. Discussed R2 resection outcome and HER2-positive NGS result; referral for consideration of HER2-directed therapy.',
        (SELECT id FROM tbl_severity_type WHERE severity LIKE 'Grade 2%'),
        (SELECT id FROM tbl_adverse_reaction_definition WHERE adverse_reaction = 'Abdominal Pain'),
        (SELECT id FROM tbl_consultation_type WHERE name = 'Surgical Oncologist / Surgeon'),
        (SELECT id FROM tbl_discipline WHERE title = 'Surgeon'),
        (SELECT id FROM tbl_grade WHERE name LIKE 'PS 1:%'),
        '26.8');
SET @p8_ma = LAST_INSERT_ID();

INSERT INTO tbl_root_event (created_date, modified_date, created_by, modified_by, event_type_id, event_date, responsible_user_id, patient_id, note, event_status_id, event_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), UNIX_TIMESTAMP('2026-03-05')*1000,
        2, @p8, 'Follow-up after percutaneous drainage of a post-operative bile leak.',
        (SELECT id FROM tbl_event_status WHERE title = 'Completed'), @p8_ma);
INSERT INTO tbl_event_log (created_date, modified_date, created_by, modified_by, log_level, event_id, action_type, event_type_id, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', @p8_ma, 'CREATE', (SELECT id FROM tbl_event_type WHERE event_name = 'MEDICAL ASSESSMENT'), 'Created event | Type: MEDICAL ASSESSMENT | Follow-up after bile leak drainage');

-- Patient-level status note
INSERT INTO tbl_status (created_date, modified_date, created_by, modified_by, patient_id, status_type_id, date, height, weight, note, responsible_user_id)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, @p8, (SELECT id FROM tbl_status_type WHERE status_name = 'Active'), UNIX_TIMESTAMP('2026-03-05')*1000,
        '174', '81', 'Alive with locally advanced, R2-resected (macroscopic residual) HER2-positive gallbladder adenocarcinoma with hepatic invasion; recovering from a post-operative bile leak, HER2-directed therapy under MDT discussion.', 2);
SET @p8_status = LAST_INSERT_ID();
INSERT INTO tbl_status_log (created_date, modified_date, created_by, modified_by, log_level, entity_type, entity_id, action_type, description)
VALUES (UNIX_TIMESTAMP(NOW())*1000, UNIX_TIMESTAMP(NOW())*1000, @app_user_id, @app_user_id, 'INFO', 'STATUS', @p8_status, 'CREATE', 'Created status: Alive with locally advanced R2-resected HER2-positive gallbladder cancer');



-- ============================================================================
-- END OF BATCH 2
-- ============================================================================
