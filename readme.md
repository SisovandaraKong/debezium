# Oracle CDC with OpenLogReplicator, Debezium & Kafka

Real-time Change Data Capture (CDC) pipeline for Oracle Database using OpenLogReplicator and Debezium with Apache Kafka.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## 🎯 Overview

This project implements a production-ready Change Data Capture (CDC) pipeline that captures real-time data changes from Oracle Database and streams them to Apache Kafka.

### Key Features

- ✅ Real-time data capture (100ms - 2s latency)
- ✅ Low database overhead (uses redo logs, not queries)
- ✅ Guaranteed data consistency
- ✅ SSL-secured Kafka cluster
- ✅ Avro schema management
- ✅ Horizontal scalability
- ✅ Production-ready configuration

### Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Oracle Database | 19.3.0-ee | Source database |
| OpenLogReplicator | 1.8.7 | Redo log reader |
| Debezium | 3.0 | CDC connector |
| Apache Kafka | 7.8.0 | Event streaming |
| Schema Registry | 7.8.0 | Schema management |

---

## 🏗️ Architecture

```
┌─────────────────┐
│ Oracle Database │ Writes changes to redo logs
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│ OpenLogReplicator   │ Reads redo logs, converts to JSON
└────────┬────────────┘
         │ Port 8080 (HTTP)
         ▼
┌─────────────────────┐
│ Debezium Connector  │ Transforms to CDC events
└────────┬────────────┘
         │ SSL (19093)
         ▼
┌─────────────────────┐
│ Kafka Cluster       │ Stores events in topics
│ (3 brokers)         │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Your Applications   │ Consume and process events
└─────────────────────┘
```

### Data Flow

1. **Oracle** commits a transaction → writes to redo log
2. **OpenLogReplicator** detects change → parses redo log → converts to JSON
3. **Debezium** receives JSON → adds metadata → creates CDC event
4. **Kafka** stores event → makes available to consumers
5. **Your apps** consume events → react to changes

---

## 📦 Prerequisites

### Required Software

- Docker 20.10+
- Docker Compose 2.0+
- 16GB RAM minimum (20GB recommended)
- 50GB free disk space

### Required Files

```
.
├── docker-compose.yml
├── Dockerfile
├── secrets/
│   ├── kafka.server.keystore.jks
│   └── kafka.server.truststore.jks
├── config/
│   └── client-ssl.properties
├── oracle-init-scripts/
│   └── 01_setup_cdc.sql
└── scripts/
    └── OpenLogReplicator.json
```

### Oracle Docker Image

You need Oracle Database 19c Enterprise Edition Docker image:

```bash
# Login to Oracle Container Registry
docker login container-registry.oracle.com

# Pull the image
docker pull container-registry.oracle.com/database/enterprise:19.3.0.0
```

---

## 🚀 Quick Start

### Step 1: Clone and Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd <project-directory>

# Create required directories
mkdir -p checkpoint log output scripts secrets config csv-data oracle-init-scripts

# Copy your SSL certificates to secrets/
cp /path/to/kafka.server.keystore.jks secrets/
cp /path/to/kafka.server.truststore.jks secrets/
```

### Step 2: Start Infrastructure

```bash
# Start Oracle database (takes 3-5 minutes)
docker-compose up -d oracle

# Wait for Oracle to be ready
docker logs -f oracle19c
# Wait for: "DATABASE IS READY TO USE!"

# Start Kafka cluster
docker-compose up -d kafka-1 kafka-2 kafka-3 schema-registry

# Wait 30 seconds for Kafka to stabilize
sleep 30
```

### Step 3: Start CDC Components

```bash
# Start OpenLogReplicator
docker-compose up -d openlogreplicator

# Check OpenLogReplicator logs
docker logs openlogreplicator
# Should see: "connected to Oracle Database"

# Start Debezium Kafka Connect
docker-compose up -d debezium-kafka-connect

# Wait for Debezium to be ready
docker logs -f debezium-kafka-connect
# Wait for: "Kafka Connect started"
```

### Step 4: Create Debezium Connector

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connector-config.json
```

### Step 5: Verify CDC is Working

```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-olr-connector/status | jq

# List Kafka topics
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:19093 \
  --command-config /etc/kafka/config/client-ssl.properties \
  --list

# Consume CDC events
docker exec kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:19093 \
  --consumer.config /etc/kafka/config/client-ssl.properties \
  --topic oracle_server.C__DBZUSER.CUSTOMERS \
  --from-beginning
```

### Step 6: Test with Data Changes

```bash
# Insert a new record
docker exec oracle19c sqlplus c##dbzuser/dbz@localhost:1521/ORCLPDB1 <<EOF
INSERT INTO customers (id, name, email) 
VALUES (9001, 'Test User', 'test@example.com');
COMMIT;
EXIT;
EOF

# Watch for the CDC event (should appear within 1-2 seconds)
```

---

## ⚙️ Configuration

### Oracle Database

**Location:** `./oracle-init-scripts/01_setup_cdc.sql`

Key configurations:
- Archive log mode: ENABLED
- Supplemental logging: MIN + ALL COLUMNS
- CDC user: `c##dbzuser` with required privileges
- Test table: `CUSTOMERS` (4 initial rows)

### OpenLogReplicator

**Location:** `./scripts/OpenLogReplicator.json`

```json
{
  "version": "1.8.7",
  "source": [{
    "alias": "SOURCE",
    "name": "ORACLE",
    "reader": {
      "type": "online",
      "path-mapping": [
        "/opt/oracle/oradata", "/opt/oradata",
        "/opt/oracle/fra", "/opt/fra"
      ],
      "user": "c##dbzuser",
      "password": "dbz",
      "server": "//oracle19c:1521/ORCLPDB1"
    },
    "format": {
      "type": "json",
      "column": 2,
      "db": 3,
      "interval-dts": 9,
      "interval-ytm": 4,
      "message": 2,
      "rid": 1,
      "schema": 7
    }
  }],
  "target": [{
    "alias": "DEBEZIUM",
    "source": "SOURCE",
    "writer": {
      "type": "network",
      "uri": "0.0.0.0:8080"
    }
  }]
}
```

### Debezium Connector

**Create via REST API** (see connector-config.json)

Key settings:
- Adapter: OpenLogReplicator (`olr`)
- Tables: `C##DBZUSER.CUSTOMERS`
- Topic prefix: `oracle_server`
- SSL: Enabled for Kafka communication

---

## 📊 Usage

### Connecting to Oracle with DataGrip

```
Host: localhost
Port: 1521
Connection type: Service name
Service name: ORCLPDB1
User: c##dbzuser
Password: dbz
```

### SQL Operations

**View data:**
```sql
SELECT * FROM customers ORDER BY id;
```

**Insert record:**
```sql
INSERT INTO customers (id, name, email) 
VALUES (2001, 'John Doe', 'john@example.com');
COMMIT;
```

**Update record:**
```sql
UPDATE customers 
SET email = 'newemail@example.com' 
WHERE id = 2001;
COMMIT;
```

**Delete record:**
```sql
DELETE FROM customers WHERE id = 2001;
COMMIT;
```

### Consuming CDC Events

**Using Kafka Console Consumer:**
```bash
docker exec kafka-1 kafka-console-consumer \
  --bootstrap-server kafka-1:19093 \
  --consumer.config /etc/kafka/config/client-ssl.properties \
  --topic oracle_server.C__DBZUSER.CUSTOMERS \
  --from-beginning
```

**CDC Event Structure:**
```json
{
  "before": null,
  "after": {
    "ID": 9001,
    "NAME": "Test User",
    "EMAIL": "test@example.com",
    "CREATED_DATE": 1703174400000
  },
  "source": {
    "version": "3.0.0",
    "connector": "oracle",
    "name": "oracle_server",
    "ts_ms": 1703174400000,
    "snapshot": "false",
    "db": "ORCLCDB",
    "schema": "C##DBZUSER",
    "table": "CUSTOMERS",
    "scn": "1234567"
  },
  "op": "c",
  "ts_ms": 1703174400123
}
```

**Operation types:**
- `c` = CREATE (INSERT)
- `u` = UPDATE
- `d` = DELETE
- `r` = READ (snapshot)

---

## 🔍 Monitoring

### Check Container Status

```bash
# All containers
docker-compose ps

# Specific container logs
docker logs -f oracle19c
docker logs -f openlogreplicator
docker logs -f debezium-kafka-connect
```

### Monitor OpenLogReplicator

```bash
# Check if connected to Oracle
docker logs openlogreplicator | grep "connected to Oracle"

# Check if listening on port 8080
docker exec openlogreplicator netstat -tuln | grep 8080
```

### Monitor Debezium Connector

```bash
# Connector status
curl -s http://localhost:8083/connectors/oracle-olr-connector/status | jq

# Connector config
curl -s http://localhost:8083/connectors/oracle-olr-connector | jq

# Available connectors
curl -s http://localhost:8083/connectors | jq
```

### Monitor Kafka

```bash
# List topics
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:19093 \
  --command-config /etc/kafka/config/client-ssl.properties \
  --list

# Describe topic
docker exec kafka-1 kafka-topics \
  --bootstrap-server kafka-1:19093 \
  --command-config /etc/kafka/config/client-ssl.properties \
  --describe \
  --topic oracle_server.C__DBZUSER.CUSTOMERS

# Check consumer lag
docker exec kafka-1 kafka-consumer-groups \
  --bootstrap-server kafka-1:19093 \
  --command-config /etc/kafka/config/client-ssl.properties \
  --describe \
  --group your-consumer-group
```

### Access Kafka UI

Open browser: http://localhost:18000

```
Username: admin
Password: admin-secret
```

---

## 🔧 Troubleshooting

### Oracle Issues

**Problem: Container won't start**
```bash
# Check logs
docker logs oracle19c

# Common issue: Not enough memory
# Solution: Increase Docker memory to 8GB+
```

**Problem: Can't connect to Oracle**
```bash
# Check if PDB is open
docker exec oracle19c sqlplus / as sysdba <<EOF
SELECT name, open_mode FROM v\$pdbs;
EXIT;
EOF

# If not open, open it
docker exec oracle19c sqlplus / as sysdba <<EOF
ALTER PLUGGABLE DATABASE ORCLPDB1 OPEN;
EXIT;
EOF
```

### OpenLogReplicator Issues

**Problem: "parse error, attribute scn-all not expected"**
- **Cause:** Wrong OpenLogReplicator.json format
- **Solution:** Remove `scn-all` and `timestamp-all` attributes

**Problem: "Cannot connect to Oracle"**
```bash
# Check network connectivity
docker exec openlogreplicator ping oracle19c

# Check Oracle is ready
docker logs oracle19c | grep "DATABASE IS READY"

# Verify credentials
docker exec oracle19c sqlplus c##dbzuser/dbz@localhost:1521/ORCLPDB1
```

### Debezium Issues

**Problem: Connector fails to start**
```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-olr-connector/status | jq

# Check logs
docker logs debezium-kafka-connect | grep ERROR

# Delete and recreate connector
curl -X DELETE http://localhost:8083/connectors/oracle-olr-connector
# Then recreate with POST
```

**Problem: "Cannot connect to OpenLogReplicator"**
```bash
# Test connection
docker exec debezium-kafka-connect curl -v http://openlogreplicator:8080

# Check OpenLogReplicator is listening
docker exec openlogreplicator netstat -tuln | grep 8080
```

### Kafka Issues

**Problem: SSL connection errors**
- Check certificates are mounted: `docker exec kafka-1 ls /etc/kafka/secrets/`
- Verify passwords in docker-compose.yml match certificate passwords
- Check SSL configuration in connector config

**Problem: Topics not created**
```bash
# Check if auto.create.topics.enable is true
docker exec kafka-1 kafka-configs \
  --bootstrap-server kafka-1:19093 \
  --command-config /etc/kafka/config/client-ssl.properties \
  --describe \
  --entity-type brokers \
  --entity-default
```

---

## 🎓 Advanced Topics

### Adding More Tables

Edit connector config:
```json
{
  "table.include.list": "C##DBZUSER.CUSTOMERS,C##DBZUSER.ORDERS,C##DBZUSER.PRODUCTS"
}
```

For each new table in Oracle:
```sql
-- Enable supplemental logging
ALTER TABLE c##dbzuser.orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

### Scaling

**Add more Kafka brokers:**
```yaml
# Add to docker-compose.yml
kafka-4:
  image: confluentinc/cp-kafka:7.8.0
  # ... similar config to kafka-1/2/3
```

**Increase Debezium tasks:**
```json
{
  "tasks.max": "3"  // For multiple tables
}
```

### Performance Tuning

**Oracle:**
- Increase redo log size: 400MB+ for high-volume changes
- Monitor archive log generation rate
- Consider separate FRA (Fast Recovery Area)

**OpenLogReplicator:**
- Adjust log-level for production: `"log-level": 1`
- Use online catalog for better performance

**Debezium:**
- Tune `max.batch.size` for throughput
- Adjust `poll.interval.ms` for latency
- Use `snapshot.mode: schema_only` to skip initial snapshot

**Kafka:**
- Increase `num.partitions` for parallelism
- Tune `compression.type` (lz4 or snappy)
- Adjust retention policies

### Backup and Recovery

**Backup Kafka topics:**
```bash
kafka-mirror-maker \
  --consumer.config consumer.properties \
  --producer.config producer.properties \
  --whitelist "oracle_server.*"
```

**Backup Oracle:**
```bash
# RMAN backup
docker exec oracle19c rman target / <<EOF
BACKUP DATABASE PLUS ARCHIVELOG;
EXIT;
EOF
```

---

## 📚 References

- [Debezium Documentation](https://debezium.io/documentation/)
- [OpenLogReplicator GitHub](https://github.com/bersler/OpenLogReplicator)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Oracle Database Documentation](https://docs.oracle.com/en/database/)

---
