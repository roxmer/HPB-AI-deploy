-- Clinician: Bulk Import menu on the test server (2026-11-10).
--
-- V1_1_145 creates BULK_IMPORT_C but deliberately grants it to no role, and bootstrap_roles_clinician_researcher.sql
-- copies from Super Admin what Super Admin holds in tbl_role_authority, so on a clean install the Clinician has no
-- Bulk Import menu (the menu entry needs BULK_IMPORT_C, static/js/util/NavUtil.js). Locally it was granted by hand.
-- Researcher is NOT granted it (decision of update_role_researcher_2026-10-09.sql).
-- Running an import also needs the create rights of what is imported (EVENT_C, LAB_TEST_RESULT_C ...); the check at
-- the end lists them. Idempotent; the Clinician logs in again to see the menu.

INSERT INTO tbl_role_authority (role_id, authority_id)
SELECT r.id, a.id
FROM tbl_role r
    JOIN tbl_authority a ON a.title = 'BULK_IMPORT_C'
WHERE r.title = 'Clinician'
  AND NOT EXISTS (SELECT 1 FROM tbl_role_authority x WHERE x.role_id = r.id AND x.authority_id = a.id);

-- check: must list BULK_IMPORT_C and the create rights the import needs
SELECT r.title AS role, a.title AS authority
FROM tbl_role_authority ra
    JOIN tbl_authority a ON a.id = ra.authority_id
    JOIN tbl_role r ON r.id = ra.role_id
WHERE r.title = 'Clinician' AND a.title IN ('BULK_IMPORT_C', 'EVENT_C', 'LAB_TEST_RESULT_C', 'EVENT_RADIOLOGY_C')
ORDER BY a.title;
