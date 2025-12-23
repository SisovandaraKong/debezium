-- ============================================
-- Oracle CDC Setup Script for OpenLogReplicator + Debezium
-- This runs automatically when Oracle starts
-- Place this file in ./oracle-init-scripts/
-- ============================================

-- Note: Archive log mode is already enabled via ENABLE_ARCHIVELOG: "true" in docker-compose
-- Note: Script runs as SYSDBA automatically

-- ============================================
-- SECTION 1: Configure Archive Log Destination (CRITICAL for OpenLogReplicator)
-- ============================================

-- Set Fast Recovery Area (FRA) size and location
-- OpenLogReplicator needs access to archived redo logs
ALTER SYSTEM SET db_recovery_file_dest_size = 10G;
ALTER SYSTEM SET db_recovery_file_dest = '/opt/oracle/oradata/ORCLCDB' SCOPE=SPFILE;

-- Verify archive log mode (should already be enabled by docker-compose)
-- If not enabled, uncomment below:
-- SHUTDOWN IMMEDIATE;
-- STARTUP MOUNT;
-- ALTER DATABASE ARCHIVELOG;
-- ALTER DATABASE OPEN;

-- ============================================
-- SECTION 2: Configure Redo Logs (400MB each)
-- ============================================

-- Larger redo logs prevent frequent log switches
-- Frequent switches can cause CDC to miss transactions
ALTER DATABASE CLEAR LOGFILE GROUP 1;
ALTER DATABASE DROP LOGFILE GROUP 1;
ALTER DATABASE ADD LOGFILE GROUP 1 ('/opt/oracle/oradata/ORCLCDB/redo01.log') SIZE 400M REUSE;

ALTER DATABASE CLEAR LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE ADD LOGFILE GROUP 2 ('/opt/oracle/oradata/ORCLCDB/redo02.log') SIZE 400M REUSE;

ALTER DATABASE CLEAR LOGFILE GROUP 3;
ALTER DATABASE DROP LOGFILE GROUP 3;
ALTER DATABASE ADD LOGFILE GROUP 3 ('/opt/oracle/oradata/ORCLCDB/redo03.log') SIZE 400M REUSE;

-- Force log switch to activate new configuration
ALTER SYSTEM SWITCH LOGFILE;

-- ============================================
-- SECTION 3: Enable Supplemental Logging (CDB Level)
-- ============================================

-- Enable minimal supplemental logging (required for CDC)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Enable supplemental logging for all columns (recommended)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================
-- SECTION 4: Create Tablespaces for CDC User
-- ============================================

-- Create tablespace at CDB level
BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE LOGMINER_TBS DATAFILE ''/opt/oracle/oradata/ORCLCDB/logminer_tbs.dbf'' SIZE 100M REUSE AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED';
  DBMS_OUTPUT.PUT_LINE('LOGMINER_TBS tablespace created in CDB.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1543 THEN -- tablespace already exists
      DBMS_OUTPUT.PUT_LINE('LOGMINER_TBS tablespace already exists in CDB.');
    ELSE
      RAISE;
    END IF;
END;
/

-- Switch to PDB and create tablespace there
ALTER SESSION SET CONTAINER=ORCLPDB1;

BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLESPACE LOGMINER_TBS DATAFILE ''/opt/oracle/oradata/ORCLCDB/ORCLPDB1/logminer_tbs.dbf'' SIZE 100M REUSE AUTOEXTEND ON NEXT 100M MAXSIZE UNLIMITED';
  DBMS_OUTPUT.PUT_LINE('LOGMINER_TBS tablespace created in PDB.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1543 THEN
      DBMS_OUTPUT.PUT_LINE('LOGMINER_TBS tablespace already exists in PDB.');
    ELSE
      RAISE;
    END IF;
END;
/

-- Switch back to CDB
ALTER SESSION SET CONTAINER=CDB$ROOT;

-- ============================================
-- SECTION 5: Create CDC User (Common User)
-- ============================================

-- Create common user for CDC (c## prefix required for CDB)
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER c##dbzuser IDENTIFIED BY dbz DEFAULT TABLESPACE LOGMINER_TBS QUOTA UNLIMITED ON LOGMINER_TBS CONTAINER=ALL';
  DBMS_OUTPUT.PUT_LINE('User c##dbzuser created.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -1920 THEN -- user already exists
      DBMS_OUTPUT.PUT_LINE('User c##dbzuser already exists.');
    ELSE
      RAISE;
    END IF;
END;
/

-- ============================================
-- SECTION 6: Grant Basic Privileges
-- ============================================

GRANT CREATE SESSION TO c##dbzuser CONTAINER=ALL;
GRANT SET CONTAINER TO c##dbzuser CONTAINER=ALL;
GRANT CONNECT TO c##dbzuser;
GRANT RESOURCE TO c##dbzuser;

-- ============================================
-- SECTION 7: Grant Database Access Privileges
-- ============================================

-- V$ views access
GRANT SELECT ON V_$DATABASE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOG TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOG_HISTORY TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$LOGFILE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVED_LOG TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVE_DEST_STATUS TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$PARAMETER TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$TRANSACTION TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$SESS_IO TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$DATAFILE TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ON V_$TABLESPACE TO c##dbzuser CONTAINER=ALL;

-- Dictionary access
GRANT SELECT ANY DICTIONARY TO c##dbzuser CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO c##dbzuser CONTAINER=ALL;
GRANT SELECT_CATALOG_ROLE TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE TO c##dbzuser CONTAINER=ALL;

-- Table access
GRANT SELECT ANY TABLE TO c##dbzuser CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO c##dbzuser CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 8: Grant LogMiner Privileges
-- ============================================

GRANT CREATE TABLE TO c##dbzuser CONTAINER=ALL;
GRANT CREATE SEQUENCE TO c##dbzuser CONTAINER=ALL;

GRANT EXECUTE ON DBMS_LOGMNR TO c##dbzuser CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO c##dbzuser CONTAINER=ALL;

-- ============================================
-- SECTION 9: OpenLogReplicator-Specific Grants (PDB Level)
-- ============================================

-- Switch to PDB for OpenLogReplicator specific grants
ALTER SESSION SET CONTAINER=ORCLPDB1;

-- Grant access to Oracle system tables (CRITICAL for OpenLogReplicator)
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

-- XDB table grants for OpenLogReplicator
GRANT SELECT, FLASHBACK ON XDB.XDB$TTSET TO c##dbzuser;

-- Grant on XDB internal tables (if they exist)
BEGIN
  FOR t IN (
    SELECT owner, table_name
    FROM dba_tables
    WHERE owner = 'XDB'
      AND (table_name LIKE 'X$NM%'
           OR table_name LIKE 'X$PT%'
           OR table_name LIKE 'X$QN%'
           OR table_name LIKE 'X$%')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'GRANT SELECT, FLASHBACK ON ' || t.owner || '."' || t.table_name || '" TO c##dbzuser';
    EXCEPTION
      WHEN OTHERS THEN
        NULL; -- Ignore errors for tables that don't support grants
    END;
  END LOOP;
END;
/

-- ============================================
-- SECTION 10: Create Test Table
-- ============================================

-- Create test table
BEGIN
  EXECUTE IMMEDIATE 'CREATE TABLE c##dbzuser.customers (
    id NUMBER(10) PRIMARY KEY,
    name VARCHAR2(100) NOT NULL,
    email VARCHAR2(100),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )';
  DBMS_OUTPUT.PUT_LINE('Table customers created.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -955 THEN -- table already exists
      DBMS_OUTPUT.PUT_LINE('Table customers already exists.');
    ELSE
      RAISE;
    END IF;
END;
/

-- Enable supplemental logging on the table (CRITICAL!)
ALTER TABLE c##dbzuser.customers ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ============================================
-- SECTION 11: Insert Test Data
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
-- SECTION 12: Fix File Permissions for OpenLogReplicator (CRITICAL!)
-- ============================================

-- This section must run AFTER Oracle creates the redo logs
-- Execute this as a post-startup script or manually

-- Note: This will be handled by a separate shell script
-- that runs after Oracle is fully started

-- ============================================
-- SECTION 13: Verification Queries
-- ============================================

-- Switch back to CDB for verification
ALTER SESSION SET CONTAINER=CDB$ROOT;

-- Check archive log mode
SELECT 'Archive Log Mode:' as info FROM DUAL;
SELECT LOG_MODE, SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;

-- Check redo log sizes
SELECT 'Redo Log Configuration:' as info FROM DUAL;
SELECT GROUP#, BYTES/1024/1024 as SIZE_MB, MEMBERS, STATUS FROM V$LOG ORDER BY GROUP#;

-- Verify CDC user
SELECT 'CDC User:' as info FROM DUAL;
SELECT username, account_status, default_tablespace FROM DBA_USERS WHERE username = 'C##DBZUSER';

-- Switch to PDB for table verification
ALTER SESSION SET CONTAINER=ORCLPDB1;

-- Check table supplemental logging
SELECT 'Table Supplemental Logging:' as info FROM DUAL;
SELECT table_name, log_group_type 
FROM ALL_LOG_GROUPS 
WHERE owner = 'C##DBZUSER' 
  AND table_name = 'CUSTOMERS';

-- Verify test data
SELECT 'Test Data Count:' as info FROM DUAL;
SELECT COUNT(*) as row_count FROM c##dbzuser.customers;

-- Verify OpenLogReplicator grants
SELECT 'OpenLogReplicator System Grants:' as info FROM DUAL;
SELECT COUNT(*) as grant_count
FROM DBA_TAB_PRIVS 
WHERE grantee = 'C##DBZUSER' 
  AND owner = 'SYS'
  AND table_name IN ('CCOL$', 'CDEF$', 'COL$', 'OBJ$', 'TAB$');

SELECT '========================================' AS info FROM DUAL;
SELECT 'Oracle CDC Setup Completed Successfully!' AS info FROM DUAL;
SELECT '========================================' AS info FROM DUAL;
SELECT 'IMPORTANT: Run fix-permissions.sh after Oracle starts!' AS info FROM DUAL;
SELECT '========================================' AS info FROM DUAL;

EXIT;