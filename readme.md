
# Change Data Capture (CDC) with Timescale - Proof of Concept

This repository provides a fully containerized proof of concept (PoC) demonstrating a Change Data Capture (CDC) pipeline using TimescaleDB, Kafka, Kafka Connect, and the JDBC Source Connector.

The goal is to capture changes in a PostgreSQL/Timescale table or view and stream them as events into Kafka, where downstream consumers can react in real time.

## Architecture Overview

![Architecture Overview](diagram.png)


### 🐳  Components

**🐘 TimescaleDB (timescaledb)**
- https://www.timescale.com
- Runs PostgreSQL 17 with Timescale extension
- initialized with `timescale/init.sql`
- 2 Schemas:
- dataschema.customers table with sample data
- dataschema.anomaly hypertable with sample time series data
- cdc.cdc_log hypertable that records row-level changes to the tables under surveillance.
- cdc.cdc_view_customers view exposing changes from the customers table.
- Exposed port: localhost:5432
- Database: demo
- Credentials: postgres/password

**📦 Kafka (kafka)**
- https://kafka.apache.org/
- KRaft mode (no Zookeeper)
- Acts as the message broker for the CDC events.
- Topic `cdc-event_log` will receive all the CDC records
- Topic `cdc-event_log_customers` will receive changes from the `customers` table

**🔌 Kafka Connect (kafka-connect)**
- https://kafka.apache.org/documentation.html#connect
- Uses the Aiven JDBC Source Connector mounted from `aiven-jdbc/`
- Configured via  `connectors/cdc-timescale-connector.json`
- Pulls new records from the CDC views
- Streams them to Kafka in timestamp+incrementing mode
- Management API http://localhost:8083

**🌐 Kafka UI (kafka-ui)**
- https://github.com/provectus/kafka-ui
- Web interface to browse topics, consumers, and events
- http://localhost:8080

### 🔁 Data Flow
1.	New or updated records are written to dataschema tables (`dataschema.customers` or `dataschema.anomaly`)
2.	A trigger writes a change record into `cdc.event_log`
3.	The `cdc.event_log_customers` view filters and exposes customer records
4.	Kafka Connect polls the view every 5 seconds
5.	New entries are published to the Kafka topics
6.	Kafka consumers (e.g. Python scripts or Java apps) can subscribe and act on the data


# 🚀 Getting Started

**Prerequisites**

To work with this repo you'll need:

* [Docker](https://www.docker.com/)
* Your favorite terminal
* Your favorite Postrgresql client (optional)

**1. Clone the Repo**

```
git clone https://github.com/carlospsikick/timescale-cdc.git
cd timescale-cdc
```

**2. Download and extract the JDBC Connector**

We will use Aiven JDBC Connector for Apache Kafka for this PoC. The latest releases can be found in their github repo: 
https://github.com/Aiven-Open/jdbc-connector-for-apache-kafka

```
mkdir -p aiven-jdbc
curl -L https://github.com/Aiven-Open/jdbc-connector-for-apache-kafka/releases/download/v6.10.0/jdbc-connector-for-apache-kafka-6.10.0.zip -o aiven-jdbc.zip
unzip aiven-jdbc.zip -d aiven-jdbc
```

**3. Build and Launch the Stack**

```
docker compose up --build -d
```

The containers are configured to wait until the Kafka Cluster is healthy. Kafka Connect will take about 90 seconds to fully start.
Check the docker logs for more details.


**4. Insert Test Data**

The Timescale database is accessible at:

```
url: "jdbc:postgresql://timescaledb:5432/demo"
user: "postgres"
password: "password"
```

You can use your favorite Postgresql client or the container binaries like this:

```
docker exec -it timescaledb psql -U postgres -d demo -c \
  "INSERT INTO dataschema.customers (name, email) VALUES ('Alex', 'alex@example.com');"

docker exec -it timescaledb psql -U postgres -d demo -c \
"INSERT INTO dataschema.anomaly (ts, sensorid, event) VALUES (NOW() - INTERVAL '1 hour', 'sensor_1', '{\"status\": \"ok\"}');"

```

Inspect the CDC records in the cdc.event_log table.

```
docker exec -it timescaledb psql -U postgres -d demo -c \
"SELECT * from cdc.event_log;"

```

**5. View Events in Kafka UI**

Open http://localhost:8080 and check the topics `cdc-event_log` and `cdc-event_log_customers`.

**Starting Over** 

Make sure to shutdown all containers and remove the volumes:

```
docker compose down -v
```


# 📁 Project Layout

```
.
├── connectors/
│   └── aiven-timescale-cdc.json      # JDBC connector config
├── kafka-connect/
│   ├── startup.sh                    # Creates internal Kafka Connect topics
│   └── launch-connector.sh           # Registers the connector on launch
├── aiven-jdbc/
│   └── (Aiven connector JAR + libs)  # Downloaded from the project releases page
├── timescale/
│   └── init.sql                      # Demo schemas and view definitions
├── docker-compose.yml
└── README.md

```

# ⚠️ Disclaimer

This project is intended for educational purposes only and is not designed for use in production environments. Please ensure that you review and comply with the licenses of all included components and dependencies before using this project.
