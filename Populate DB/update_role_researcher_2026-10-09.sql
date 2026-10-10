-- Role "Researcher" (for testing, 2026-10-09). Run AFTER the app has started once with migration V1_1_167
-- (it creates the authorities EVENT_DATE_RA, EVENT_NOTE_RA, EVENT_RESPONSIBLE_RA, PATIENT_COMPLETE_REPORT_RA)
-- and after update_role_clinician_2026-10-07.sql.
--
-- Rule: Researcher starts from the Clinician set (no Setting / Role Management menus), then loses:
--   * the complete patient report and the patient report PDFs, and PATIENT_RA (patient names stay hidden)
--   * creating, editing and deleting events of every type, and Bulk Import (it creates events)
--   * seeing event date, event note and event responsible user (read stays for the event itself)
-- Everything else of the Clinician set stays. Running it again changes nothing.

SET @role := (SELECT id FROM tbl_role WHERE title = 'Researcher');
SET @clin := (SELECT id FROM tbl_role WHERE title = 'Clinician');

-- Step 1: Researcher = exactly the Clinician set
DELETE FROM tbl_role_authority
WHERE role_id = @role AND @clin IS NOT NULL
  AND authority_id NOT IN (SELECT authority_id FROM (SELECT authority_id FROM tbl_role_authority WHERE role_id = @clin) c);

INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT @role, ra.authority_id FROM tbl_role_authority ra
WHERE ra.role_id = @clin AND @role IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = @role AND x.authority_id = ra.authority_id);

-- Step 2: take the Researcher restrictions away
DELETE ra FROM tbl_role_authority ra JOIN tbl_authority a ON a.id = ra.authority_id
WHERE ra.role_id = @role
  AND a.title IN (
    'PATIENT_RA', 'PATIENT_COMPLETE_REPORT_RA',
    'EVENT_DATE_RA', 'EVENT_NOTE_RA', 'EVENT_RESPONSIBLE_RA',
    'EVENT_C', 'EVENT_U', 'EVENT_D',
    'EVENT_BLOOD_SAMPLING_C', 'EVENT_BLOOD_SAMPLING_U', 'EVENT_BLOOD_SAMPLING_D',
    'EVENT_MEDICAL_ASSESSMENT_C', 'EVENT_MEDICAL_ASSESSMENT_U', 'EVENT_MEDICAL_ASSESSMENT_D',
    'EVENT_RADIOLOGY_C', 'EVENT_RADIOLOGY_U', 'EVENT_RADIOLOGY_D',
    'EVENT_SURGERY_C', 'EVENT_SURGERY_U', 'EVENT_SURGERY_D',
    'LAB_TEST_C', 'LAB_TEST_U', 'LAB_TEST_D',
    'LAB_TEST_RESULT_C', 'LAB_TEST_RESULT_U', 'LAB_TEST_RESULT_D',
    'PATHOLOGY_C', 'PATHOLOGY_U', 'PATHOLOGY_D',
    'SYSTEMIC_THERAPY_C', 'SYSTEMIC_THERAPY_U', 'SYSTEMIC_THERAPY_D',
    'TISSUE_SAMPLING_C', 'TISSUE_SAMPLING_U', 'TISSUE_SAMPLING_D',
    'BULK_IMPORT', 'BULK_IMPORT_C'
  );

-- Check 1: authority count, and the restricted ones still present (must be 0 rows)
SELECT COUNT(*) AS researcher_authorities FROM tbl_role_authority WHERE role_id = @role;
SELECT a.title AS must_be_empty FROM tbl_role_authority ra JOIN tbl_authority a ON a.id = ra.authority_id
WHERE ra.role_id = @role AND a.title IN ('PATIENT_RA','PATIENT_COMPLETE_REPORT_RA','EVENT_DATE_RA','EVENT_NOTE_RA','EVENT_RESPONSIBLE_RA','EVENT_C','EVENT_U','EVENT_D','BULK_IMPORT_C');
-- Check 2: what Researcher has that Clinician does not (must be 0 rows)
SELECT a.title AS more_than_clinician FROM tbl_role_authority ra JOIN tbl_authority a ON a.id = ra.authority_id
WHERE ra.role_id = @role AND NOT EXISTS (SELECT 1 FROM tbl_role_authority c WHERE c.role_id = @clin AND c.authority_id = ra.authority_id);
