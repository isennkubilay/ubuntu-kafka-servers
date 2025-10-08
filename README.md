# Kafka Cluster Setup

Production-ready Apache Kafka 4.1.0 cluster with KRaft mode (no Zookeeper).

## 🚀 Quick Start

### Taskfile.yml Commands

```bash
# Build Docker image
task build

# Initialize cluster
task init

# Start cluster
task start

# Check status
task status

# Open Kafka UI
task ui
```

## Kafka-ui

```bash
task kafka-ui-init
```

## 📡 Connecting Your Application

### From Host Machine (Mac):

```sh
localhost:9092,localhost:9192,localhost:9292
```

### From Docker Container:

```sh
10.20.0.10:9092,10.20.0.11:9092,10.20.0.12:9092
```

## 🛠️ Management Commands

```bash
task status                           # Cluster status
TOPIC=test-topic task create-topic    # Create topic
task list-topics                      # List all topics
task --help                           # Full help
task ps                               # Show containers
```

## 🧪 Testing

```bash
# Python example
python3 test-kafka-connection.py

# Command line (install kcat first)
brew install kcat
kcat -b localhost:9092 -L
```

## 📊 Cluster Info

- **Brokers**: 3 nodes (kafka1, kafka2, kafka3)
- __Network__: 10.20.0.0/24 (ubuntu-servers_kafka-net)
- **Data**: ./kafka-data/{kafka1,kafka2,kafka3}
- **Logs**: ./kafka-logs/{kafka1,kafka2,kafka3}
- **Kafka UI**: http://localhost:8080

## 🔧 Files

- `docker-compose.prod.yml` - Production cluster configuration
- `Taskfile.yml` - Management script (20+ commands)
- `kafka-config/server*.properties` - Kafka configurations
- `test-kafka-connection.py` - Python connection example
