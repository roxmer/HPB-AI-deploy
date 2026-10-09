-- Lab test lookup revision (2026-10-06), for a database that ALREADY contains the lab lookups.
-- A fresh database does not need this: the revised Technique_TestName_TestResult_TestUnit_export.xlsx
-- already has these values. Re-importing that workbook cannot change rows that exist, hence this script.
--
--   1) CA 19-9, unit U/mL: Min = 0 (upper limit 37 stays). The application stores a numeric value and a
--      flag (LOW / NORMAL / HIGH) only when a unit has BOTH limits, so imported and manual CA 19-9
--      results now keep their number and flag.
--   2) AST and ALT: result category 'Low' is renamed 'Decreased', like every other test.
--
-- Run once, against the application database, e.g.:
--   mysql -u <user> -p --protocol=TCP -h 127.0.0.1 <database> < "Populate DB/update_lab_lookup_revision_2026-10-06.sql"
-- It only touches rows that still have the old values, so running it twice changes nothing more.

UPDATE tbl_test_unit u
    JOIN tbl_test_name n ON n.id = u.test_name_id
SET u.min = '0', u.modified_date = UNIX_TIMESTAMP(NOW()) * 1000
WHERE n.name = 'CA 19-9' AND u.unit = 'U/mL' AND (u.min IS NULL OR TRIM(u.min) = '');

UPDATE tbl_test_result r
    JOIN tbl_test_name n ON n.id = r.test_name_id
SET r.name = 'Decreased', r.modified_date = UNIX_TIMESTAMP(NOW()) * 1000
WHERE n.name IN ('AST', 'ALT') AND r.name = 'Low';

-- Check (both should show the new values):
SELECT n.name AS test_name, u.unit, u.min, u.max FROM tbl_test_unit u JOIN tbl_test_name n ON n.id = u.test_name_id WHERE n.name = 'CA 19-9';
SELECT n.name AS test_name, r.name AS result FROM tbl_test_result r JOIN tbl_test_name n ON n.id = r.test_name_id WHERE n.name IN ('AST', 'ALT') ORDER BY n.name, r.id;
