# Kafka Cluster Setup

Production-ready Apache Kafka 4.1.0 cluster with KRaft mode (no Zookeeper).

`sudo docker build -t sshimage:ubuntu-prod -f Dockerfile.prod .`

## 🚀 Quick Start

```bash
# Initialize cluster
./kafka-cluster-prod.sh init

# Start cluster
./kafka-cluster-prod.sh start

# Check status
./kafka-cluster-prod.sh status

# Open Kafka UI
open http://localhost:8080
```

```bash
`sudo docker compose -f docker-compose-kafka-ui.yaml up -d`
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
./kafka-cluster-prod.sh status          # Cluster status
./kafka-cluster-prod.sh create-topic    # Create topic
./kafka-cluster-prod.sh list-topics     # List all topics
./kafka-cluster-prod.sh --help          # Full help
./show-connection-info.sh               # Show connection info
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
- `kafka-cluster-prod.sh` - Management script (20+ commands)
- `kafka-config/server*.properties` - Kafka configurations
- `test-kafka-connection.py` - Python connection example
