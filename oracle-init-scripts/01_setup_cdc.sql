-- ============================================
-- Oracle CDC Setup Script (CORRECTED VERSION)
-- For: Debezium + OpenLogReplicator
-- Container: Oracle 19c Enterprise Edition
-- ============================================
-- This script runs automatically during Oracle container startup
-- It configures the database for Change Data Capture (CDC)
-- ============================================

-- ============================================
-- SECTION 1: CDB-Level Supplemental Logging
-- ============================================

-- Enable minimal supplemental logging (required for CDC)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable supplemental logging for all columns (recommended for better CDC coverage)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================
-- SECTION 2: Create CDC User (Common User)
-- ============================================

-- Create common user for CDC operations
-- Note: c## prefix is required for common users in Container Database (CDB)
CREATE USER c##dbzuser IDENTIFIED BY dbz
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

-- ============================================
-- SECTION 3: Grant Basic Session Privileges
-- ============================================

GRANT CREATE SESSION TO c##dbzuser CONTAINER=ALL;
GRANT SET CONTAINER TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 4: Grant Database Access Privileges
-- ============================================

GRANT SELECT ON V_$DATABASE TO c##dbzuser CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ANY TABLE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ANY DICTIONARY TO c##dbzuser CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 5: Grant LogMiner Privileges
-- (Required for Debezium - even with OpenLogReplicator)
-- ============================================

GRANT LOGMINING TO c##dbzuser CONTAINER=ALL;
GRANT CREATE TABLE TO c##dbzuser CONTAINER=ALL;
GRANT CREATE SEQUENCE TO c##dbzuser CONTAINER=ALL;

-- Grant access to LogMiner packages
GRANT EXECUTE ON DBMS_LOGMNR TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 6: Grant Access to V$ Views
-- (Required for LogMiner and monitoring)
-- ============================================

GRANT SELECT ON V_$LOG TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOG_HISTORY TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_LOGS TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_CONTENTS TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_PARAMETERS TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGFILE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVED_LOG TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVE_DEST_STATUS TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$TRANSACTION TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$SESS_IO TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$DATAFILE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$TABLESPACE TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 7: Switch to Pluggable Database (PDB)
-- ============================================

ALTER SESSION SET CONTAINER=ORCLPDB1;

-- ============================================
-- SECTION 8: OpenLogReplicator-Specific Grants
-- (Required for OpenLogReplicator to read Oracle dictionary)
-- Reference: https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-openlogreplicator-support
-- ============================================

-- Grant access to Oracle system tables
GRANT SELECT, FLASHBACK ON SYS.CCOL$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.CDEF$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.COL$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.DEFERRED_STG$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.ECOL$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.LOB$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.LOBCOMPPART$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.LOBFRAG$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.OBJ$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.TAB$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.TABCOMPART$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.TABPART$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.TABSUBPART$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.TS$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON SYS.USER$ TO c##dbzuser;
GRANT SELECT, FLASHBACK ON XDB.XDB$TTSET TO c##dbzuser;

-- ============================================
-- SECTION 9: Create Test Schema and Table
-- ============================================

-- Create test table for CDC
CREATE TABLE c##dbzuser.customers (
  id NUMBER(10) PRIMARY KEY,
  name VARCHAR2(100) NOT NULL,
  email VARCHAR2(100),
  created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Enable supplemental logging on the test table (CRITICAL!)
-- This ensures all column values are logged in redo logs
ALTER TABLE c##dbzuser.customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================
-- SECTION 10: Insert Test Data
-- ============================================

INSERT INTO c##dbzuser.customers (id, name, email) 
VALUES (1001, 'Jane Doe', 'jane@example.com');

INSERT INTO c##dbzuser.customers (id, name, email) 
VALUES (1002, 'Bob Willy', 'bob@example.com');

INSERT INTO c##dbzuser.customers (id, name, email) 
VALUES (1003, 'Eddie Murphy', 'eddie@example.com');

INSERT INTO c##dbzuser.customers (id, name, email) 
VALUES (1004, 'Anne Mary', 'anne@example.com');

COMMIT;

-- ============================================
-- SECTION 11: Verification Queries
-- (Output will appear in Oracle container logs)
-- ============================================

-- Switch back to CDB for system-level verification
ALTER SESSION SET CONTAINER=CDB$ROOT;

-- Verify archive log mode
SELECT 'Archive Log Mode Check:' AS info FROM DUAL;
SELECT LOG_MODE FROM V$DATABASE;

-- Verify supplemental logging
SELECT 'Supplemental Logging Status:' AS info FROM DUAL;
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;

-- Verify CDC user creation
SELECT 'CDC User Verification:' AS info FROM DUAL;
SELECT username, account_status, default_tablespace 
FROM DBA_USERS 
WHERE username = 'C##DBZUSER';

-- Check redo log configuration
SELECT 'Redo Log Groups:' AS info FROM DUAL;
SELECT GROUP#, THREAD#, BYTES/1024/1024 AS SIZE_MB, MEMBERS, STATUS 
FROM V$LOG 
ORDER BY GROUP#;

-- Switch to PDB for table verification
ALTER SESSION SET CONTAINER=ORCLPDB1;

-- Verify table creation
SELECT 'Test Table Verification:' AS info FROM DUAL;
SELECT table_name, tablespace_name 
FROM ALL_TABLES 
WHERE owner = 'C##DBZUSER' 
  AND table_name = 'CUSTOMERS';

-- Verify supplemental logging on table
SELECT 'Table Supplemental Logging:' AS info FROM DUAL;
SELECT table_name, log_group_name, log_group_type 
FROM ALL_LOG_GROUPS 
WHERE owner = 'C##DBZUSER' 
  AND table_name = 'CUSTOMERS';

-- Verify test data
SELECT 'Test Data Count:' AS info FROM DUAL;
SELECT COUNT(*) AS total_rows FROM c##dbzuser.customers;

-- Verify OpenLogReplicator system table grants
SELECT 'OpenLogReplicator System Grants:' AS info FROM DUAL;
SELECT table_name, privilege, grantable
FROM DBA_TAB_PRIVS 
WHERE grantee = 'C##DBZUSER' 
  AND owner = 'SYS'
  AND table_name IN ('CCOL$', 'CDEF$', 'COL$', 'OBJ$', 'TAB$')
ORDER BY table_name;

-- ============================================
-- SCRIPT COMPLETE
-- ============================================

SELECT '========================================' AS info FROM DUAL;
SELECT 'Oracle CDC Setup Completed Successfully!' AS info FROM DUAL;
SELECT '========================================' AS info FROM DUAL;

EXIT;