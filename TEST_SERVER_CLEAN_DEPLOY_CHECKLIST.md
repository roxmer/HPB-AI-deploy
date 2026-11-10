# Test server: clean deploy checklist (empty DB, 4 users, lookup lists, correct roles)

Written 2026-11-03. The full version, with the reasons, is Part J of `Server installation/HPB-AI Test Server Deployment Runbook.docx`.
Server routine: `deploy_hpb_server.sh --local-only` (resets the DB unless `--keep-db`), then the manual war swap into Tomcat.

## Result you should get
- Roles Super Admin, Clinician, Researcher, Student; users `sa@`, `doctor@` (Clinician), `researcher@`, `student@yopmail.com`.
- Lookup lists imported, no patients, Settings and Role Management visible only to Super Admin.

## Steps
1. **Server: back up** `mysqldump -u hpb_ai_user -p --protocol=TCP -h 127.0.0.1 --no-tablespaces db_dev_hpb > ~/db_dev_hpb_before_clean_<date>.sql`; the last line must be `-- Dump completed`.
2. **Mac: three rsyncs** (11.-HPB with `--exclude /opt`, ai_agent_learning, deploy_HPB without `--delete` and without the server config); commands in Runbook Part J, step 3b.
3. **Server: patch check** (must print `checked`, no `DIFF`): compare every file under `ai_agent_learning/backend_patches` with `/opt/hpb-ai/11.-HPB`.
4. **Server: copy `HPB_Templates`** from `~/hpb_staging/deploy_HPB` to `/opt/hpb-ai/deploy_HPB` (DEPLOY_DIR) and diff.
5. **Server: config check** `grep ... | grep -c CHANGE_ME` prints 0.
6. **Server: deploy with reset** `cd ~/hpb_staging/deploy_HPB/"Server installation" && bash ./deploy_hpb_server.sh --local-only`
7. **Server: import lists** (standalone copy still on 9080) `bash ./imports_server.sh ../import.csv`; expect 50 imported, 8 present, 0 failed.
8. **Server: six role scripts in order** (`Populate DB/`): bootstrap_roles_clinician_researcher, update_role_clinician_2026-10-07, update_role_researcher_2026-10-09, update_role_sampling_and_lookup_rules_2026-10-13, update_role_settings_menu_2026-11-03, update_role_researcher_no_chart_2026-11-06.
9. **Server: swap the war into Tomcat** (kill springboot, back up hpb.war, copy ROOT.war, watch catalina.out).
10. **Browser:** Super Admin sees Settings and Role Management; Clinician and Researcher do not (log in again); Researcher has no chart and no report (403); Clinician chart and report PDF (patient ID in the file name) work.
11. **Patients:** Bulk Import ds3 shifted, then TEST-A, then TEST-B; 9 of 10 rows each, `SYN-017` fails as in the source file.
12. Change the default passwords if anyone outside the team can reach the server.

Not covered: AI Assistant (no GPU on the test server); ds5 and its pathology template (not deployed).
