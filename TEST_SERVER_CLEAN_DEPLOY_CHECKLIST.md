# Test server: clean deploy checklist (empty DB, 4 users, lookup lists, correct roles)

Written 2026-11-03. Run from inside the KI network. Nothing here was run on the server by the author; the same sequence
was run locally on port 9080 (`deploy_hpb_local.sh --local-only`, then the list import).
Details: `CLEAN_INSTALL_CHECKLIST.md` (what a fresh instance contains) and `Populate DB/ROLES_README.md` (roles).

## Result you should get
- Roles: Super Admin, Clinician, Researcher, Student. Users: `sa@`, `doctor@` (Clinician), `researcher@`, `student@yopmail.com`.
- Lookup lists imported; no patients; Settings and Role Management visible only to Super Admin.

## Steps
1. **Code is on GitHub.** `roxmer/HPB-AI` main holds the application (chart in the PDF, patient ID in the PDF file name, migrations).
   `roxmer/HPB-AI-deploy` main holds this folder (lists, role scripts). Both must be pushed before the server pulls them.
2. **Back up the database** if it holds anything you want to keep (the deploy drops it):
   `mysqldump -u hpb_ai_user -p db_dev_hpb > ~/db_dev_hpb_before_clean_<date>.sql`
3. **Check `hpb_deploy.config`** (in `Server installation/`): `MYSQL_PASSWORD`, `IMPORT_USERNAME`, `IMPORT_PASSWORD` are real
   values (not `CHANGE_ME`).
4. **Deploy with a database reset** (no `--keep-db`): `./deploy_hpb_tomcat.sh` (or `deploy_hpb_server.sh`, whichever you used
   last time). Wait until Flyway has finished and the application is up.
5. **Import the lookup lists:** `BASE_URL=<server URL> ./imports_server.sh import.csv`.
   Expected: 50 imported, 8 already present, 0 failed.
6. **Run the role scripts in this order** (each is idempotent; the check queries at the end must print no rows):
   1. `Populate DB/bootstrap_roles_clinician_researcher.sql`
   2. `Populate DB/update_role_clinician_2026-10-07.sql`
   3. `Populate DB/update_role_researcher_2026-10-09.sql`
   4. `Populate DB/update_role_sampling_and_lookup_rules_2026-10-13.sql`
   5. `Populate DB/update_role_settings_menu_2026-11-03.sql` (removes Settings and Role Management from Clinician and Researcher)

   Example: `mysql -u hpb_ai_user -p db_dev_hpb < "Populate DB/<file>.sql"`
7. **Check:**
   - Database: only the 4 roles and 4 users.
   - Super Admin: Settings and Role Management visible.
   - Clinician and Researcher (log in again, rights are read at login): no Settings, no Role Management.
     Clinician: Patient, Event, Bulk Import. Researcher: no Event, no report.
   - As Clinician: open a patient, the chart opens; the complete report PDF has the chart page, and the file name contains the patient ID.
8. **Import patients** (Bulk Import, as Super Admin or Clinician): `IHPB_step1_master_ds3.0-fixed_shifted.xlsx` first, then
   `IHPB_step1_ds3.0_TEST-A_followup_scans_and_labs.xlsx`, then `IHPB_step1_ds3.0_TEST-B_later_followup.xlsx`
   (all in `Research data/` and `Research data/Test Ds Files/`).
   Expected: 9 of 10 patients each time; the `SYN-017` row fails with "date_birth is required for a new patient" (the source file);
   TEST-B skips its repeated rows as duplicates; no conflicts.
9. **Change the default passwords** of the four users if anyone outside the team can reach the server.

## Known limits
- The AI Assistant cannot be tested on the test server (no GPU).
- ds5 and its pathology template are not deployed (template v3 exists only locally); rehearse the ds5 import before using it.
- The Student role comes from the seed and is not part of the agreed role set.
