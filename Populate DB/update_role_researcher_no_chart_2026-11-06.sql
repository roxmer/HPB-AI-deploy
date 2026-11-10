-- Researcher: no disease progression chart (decision 2026-11-06).
--
-- The Researcher already has no complete patient report (PATIENT_COMPLETE_REPORT_RA is removed by
-- update_role_researcher_2026-10-09.sql). The chart is opened and served with VISUALISATION_RA
-- (ProgressionController, the chart button on the patient page, and the chart page of the report), so removing it
-- closes the chart and keeps it out of any report for this role.
-- Clinician and Super Admin are not affected. Idempotent; the Researcher logs in again to see the change.

SET @old_safe_updates := @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;

DELETE ra FROM tbl_role_authority ra
    JOIN tbl_authority a ON a.id = ra.authority_id
    JOIN tbl_role r ON r.id = ra.role_id
WHERE r.title = 'Researcher'
  AND a.title IN ('VISUALISATION_RA', 'PATIENT_COMPLETE_REPORT_RA');

SET SQL_SAFE_UPDATES = @old_safe_updates;

-- check, must be 0 rows
SELECT r.title AS role, a.title AS authority
FROM tbl_role_authority ra
    JOIN tbl_authority a ON a.id = ra.authority_id
    JOIN tbl_role r ON r.id = ra.role_id
WHERE r.title = 'Researcher' AND a.title IN ('VISUALISATION_RA', 'PATIENT_COMPLETE_REPORT_RA');

-- check, must still list both (Clinician keeps the chart and the report)
SELECT r.title AS role, a.title AS authority
FROM tbl_role_authority ra
    JOIN tbl_authority a ON a.id = ra.authority_id
    JOIN tbl_role r ON r.id = ra.role_id
WHERE r.title = 'Clinician' AND a.title IN ('VISUALISATION_RA', 'PATIENT_COMPLETE_REPORT_RA');
