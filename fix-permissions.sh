#!/bin/bash
# Fix Oracle redo log permissions for OpenLogReplicator

echo "Waiting for Oracle to be ready..."
sleep 30

echo "Fixing redo log permissions..."
docker exec oracle19c bash -c "
  # Fix redo log permissions (readable by group 54321)
  chmod 660 /opt/oracle/oradata/ORCLCDB/*.log
  chown 54321:54321 /opt/oracle/oradata/ORCLCDB/*.log
  
  # Fix directory permissions
  chmod 775 /opt/oracle/oradata/ORCLCDB/
  chown 54321:54321 /opt/oracle/oradata/ORCLCDB/
  
  echo 'Permissions fixed!'
  ls -la /opt/oracle/oradata/ORCLCDB/*.log
"

echo "Done! OpenLogReplicator should now be able to read redo logs."
