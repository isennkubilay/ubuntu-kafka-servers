#!/bin/bash
# Kafka Cluster Management Script - Production Version

set -e

COMPOSE_FILE="docker-compose.prod.yml"
CLUSTER_ID_FILE=".kafka-cluster-id"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

function print_error() {
    echo -e "${RED}✗ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

function check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check if docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "docker-compose.prod.yml not found!"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

function generate_cluster_id() {
    echo "Generating cluster ID..."
    
    # Check if cluster ID already exists
    if [ -f "$CLUSTER_ID_FILE" ]; then
        CLUSTER_ID=$(cat "$CLUSTER_ID_FILE")
        print_warning "Using existing cluster ID: $CLUSTER_ID"
        return
    fi
    
    # Generate new cluster ID using docker run
    CLUSTER_ID=$(docker run --rm --entrypoint /opt/kafka/bin/kafka-storage.sh sshimage:ubuntu-prod random-uuid)
    echo "$CLUSTER_ID" > "$CLUSTER_ID_FILE"
    print_success "Cluster ID generated: $CLUSTER_ID"
    echo "$CLUSTER_ID"
}

function format_storage() {
    if [ ! -f "$CLUSTER_ID_FILE" ]; then
        print_error "Cluster ID not found. Run 'init' first."
        exit 1
    fi
    
    CLUSTER_ID=$(cat "$CLUSTER_ID_FILE")
    
    echo "Formatting storage on all nodes with cluster ID: $CLUSTER_ID"
    
    # Create local directories for data and logs
    echo "Creating local directories..."
    mkdir -p kafka-data/{kafka1,kafka2,kafka3}
    mkdir -p kafka-logs/{kafka1,kafka2,kafka3}
    print_success "Directories created"
    
    # Ensure network exists
    if ! docker network inspect ubuntu-servers_kafka-net &> /dev/null; then
        echo "Creating Docker network..."
        docker network create ubuntu-servers_kafka-net --subnet 10.20.0.0/24 --label com.docker.compose.project=ubuntu-servers --label com.docker.compose.network=kafka-net
    fi
    
    # Format storage using temporary containers with bash entrypoint
    for i in 1 2 3; do
        NODE="kafka${i}"
        IP="10.20.0.1${i}"
        CONFIG="./kafka-config/server${i}.properties"
        DATA_DIR="$(pwd)/kafka-data/${NODE}"
        
        echo "Formatting $NODE..."
        
        docker run --rm \
            --network ubuntu-servers_kafka-net \
            --ip $IP \
            -v $DATA_DIR:/opt/kafka/kraft-data \
            -v $(pwd)/$CONFIG:/opt/kafka/config/server.properties:ro \
            --entrypoint /bin/bash \
            sshimage:ubuntu-prod \
            -c "/opt/kafka/bin/kafka-storage.sh format -t $CLUSTER_ID -c /opt/kafka/config/server.properties" \
            && print_success "$NODE formatted" || print_error "Failed to format $NODE"
    done
    
    print_success "Storage formatted on all nodes"
}

function start_kafka() {
    echo "Starting Kafka cluster..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    echo "Waiting for Kafka to start (this may take 30-60 seconds)..."
    sleep 15
    
    # Wait for health checks
    for i in {1..12}; do
        if docker ps | grep -q "healthy"; then
            print_success "Kafka cluster started successfully"
            docker-compose -f "$COMPOSE_FILE" ps
            return 0
        fi
        echo "Waiting for health checks... ($i/12)"
        sleep 5
    done
    
    print_warning "Kafka may still be starting. Check status with: $0 status"
}

function stop_kafka() {
    echo "Stopping Kafka cluster..."
    docker-compose -f "$COMPOSE_FILE" down
    print_success "Kafka cluster stopped"
}

function restart_kafka() {
    stop_kafka
    sleep 5
    start_kafka
}

function check_status() {
    echo "Checking Kafka cluster status..."
    echo ""
    
    # Check containers
    echo "=== Container Status ==="
    docker-compose -f "$COMPOSE_FILE" ps
    echo ""
    
    # Check health
    echo "=== Health Status ==="
    for node in kafka1 kafka2 kafka3; do
        if docker ps --filter "name=$node" --filter "health=healthy" | grep -q "$node"; then
            print_success "$node: Healthy"
        elif docker ps --filter "name=$node" | grep -q "$node"; then
            print_warning "$node: Starting or Unhealthy"
        else
            print_error "$node: Not running"
        fi
    done
    echo ""
    
    # Check Kafka connectivity
    echo "=== Kafka Connectivity ==="
    if docker exec kafka1 /opt/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server localhost:9092 &> /dev/null; then
        print_success "Kafka brokers are responding"
        
        # Get broker info
        docker exec kafka1 /opt/kafka/bin/kafka-broker-api-versions.sh \
            --bootstrap-server 10.20.0.10:9092 2>/dev/null | grep -E "^10.20.0" || true
    else
        print_error "Kafka brokers are not responding"
    fi
}

function view_logs() {
    NODE=${2:-kafka1}
    LINES=${3:-100}
    
    echo "Showing last $LINES lines of $NODE logs..."
    docker logs "$NODE" --tail "$LINES" --follow
}

function check_health() {
    echo "Running health checks..."
    echo ""
    
    # Check under-replicated partitions
    echo "=== Under-Replicated Partitions ==="
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --describe --under-replicated-partitions \
        --bootstrap-server 10.20.0.10:9092 2>/dev/null || echo "None"
    echo ""
    
    # Check unavailable partitions
    echo "=== Unavailable Partitions ==="
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh \
        --describe --unavailable-partitions \
        --bootstrap-server 10.20.0.10:9092 2>/dev/null || echo "None"
    echo ""
    
    # Check disk usage
    echo "=== Disk Usage ==="
    docker exec kafka1 df -h /opt/kafka/kraft-data
    docker exec kafka2 df -h /opt/kafka/kraft-data
    docker exec kafka3 df -h /opt/kafka/kraft-data
}

function create_topic() {
    if [ -z "$2" ]; then
        echo "Error: Topic name required"
        echo "Usage: $0 create-topic <topic-name> [partitions] [replication-factor]"
        exit 1
    fi
    
    TOPIC_NAME=$2
    PARTITIONS=${3:-3}
    REPLICATION=${4:-3}
    
    echo "Creating topic: $TOPIC_NAME (partitions=$PARTITIONS, replication=$REPLICATION)"
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --create \
        --bootstrap-server 10.20.0.10:9092 \
        --topic "$TOPIC_NAME" \
        --partitions "$PARTITIONS" \
        --replication-factor "$REPLICATION"
    
    print_success "Topic created: $TOPIC_NAME"
}

function delete_topic() {
    if [ -z "$2" ]; then
        echo "Error: Topic name required"
        echo "Usage: $0 delete-topic <topic-name>"
        exit 1
    fi
    
    TOPIC_NAME=$2
    
    read -p "Are you sure you want to delete topic '$TOPIC_NAME'? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo "Deleting topic: $TOPIC_NAME"
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --delete \
        --topic "$TOPIC_NAME" \
        --bootstrap-server 10.20.0.10:9092
    
    print_success "Topic deleted: $TOPIC_NAME"
}

function list_topics() {
    echo "Listing all topics..."
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --list \
        --bootstrap-server 10.20.0.10:9092
}

function describe_topic() {
    if [ -z "$2" ]; then
        echo "Error: Topic name required"
        echo "Usage: $0 describe-topic <topic-name>"
        exit 1
    fi
    
    echo "Describing topic: $2"
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe \
        --topic "$2" \
        --bootstrap-server 10.20.0.10:9092
}

function alter_topic() {
    if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        echo "Error: Topic name, config key, and value required"
        echo "Usage: $0 alter-topic <topic-name> <config-key> <config-value>"
        echo "Example: $0 alter-topic my-topic retention.ms 86400000"
        exit 1
    fi
    
    TOPIC_NAME=$2
    CONFIG_KEY=$3
    CONFIG_VALUE=$4
    
    echo "Altering topic $TOPIC_NAME: $CONFIG_KEY=$CONFIG_VALUE"
    docker exec kafka1 /opt/kafka/bin/kafka-configs.sh --alter \
        --topic "$TOPIC_NAME" \
        --add-config "$CONFIG_KEY=$CONFIG_VALUE" \
        --bootstrap-server 10.20.0.10:9092
    
    print_success "Topic configuration updated"
}

function produce_message() {
    if [ -z "$2" ]; then
        echo "Error: Topic name required"
        echo "Usage: $0 produce <topic-name>"
        exit 1
    fi
    
    echo "Starting producer for topic: $2"
    echo "Type your messages and press Enter. Press Ctrl+C to exit."
    docker exec -it kafka1 /opt/kafka/bin/kafka-console-producer.sh \
        --topic "$2" \
        --bootstrap-server 10.20.0.10:9092
}

function consume_messages() {
    if [ -z "$2" ]; then
        echo "Error: Topic name required"
        echo "Usage: $0 consume <topic-name> [from-beginning]"
        exit 1
    fi
    
    TOPIC=$2
    FROM_BEGINNING=""
    if [ "$3" = "from-beginning" ]; then
        FROM_BEGINNING="--from-beginning"
    fi
    
    echo "Starting consumer for topic: $TOPIC"
    echo "Press Ctrl+C to exit."
    docker exec -it kafka1 /opt/kafka/bin/kafka-console-consumer.sh \
        --topic "$TOPIC" \
        $FROM_BEGINNING \
        --bootstrap-server 10.20.0.10:9092
}

function cluster_info() {
    echo "Getting cluster information..."
    echo ""
    
    echo "=== Cluster Metadata ==="
    docker exec kafka1 /opt/kafka/bin/kafka-broker-api-versions.sh \
        --bootstrap-server 10.20.0.10:9092 2>/dev/null | grep -E "^10.20.0"
    echo ""
    
    echo "=== Topics Overview ==="
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe \
        --bootstrap-server 10.20.0.10:9092 2>/dev/null || echo "No topics found"
}

function list_consumer_groups() {
    echo "Listing consumer groups..."
    docker exec kafka1 /opt/kafka/bin/kafka-consumer-groups.sh --list \
        --bootstrap-server 10.20.0.10:9092
}

function describe_consumer_group() {
    if [ -z "$2" ]; then
        echo "Error: Consumer group name required"
        echo "Usage: $0 describe-group <group-name>"
        exit 1
    fi
    
    echo "Describing consumer group: $2"
    docker exec kafka1 /opt/kafka/bin/kafka-consumer-groups.sh --describe \
        --group "$2" \
        --bootstrap-server 10.20.0.10:9092
}

function backup_config() {
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    echo "Backing up configurations to $BACKUP_DIR..."
    
    # Backup compose file
    cp "$COMPOSE_FILE" "$BACKUP_DIR/"
    
    # Backup kafka configs
    cp -r kafka-config "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup cluster ID
    cp "$CLUSTER_ID_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Export topics
    docker exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe \
        --bootstrap-server 10.20.0.10:9092 > "$BACKUP_DIR/topics.txt" 2>/dev/null || true
    
    print_success "Configuration backed up to $BACKUP_DIR"
}

function open_ui() {
    echo "Opening Kafka UI in browser..."
    if command -v open &> /dev/null; then
        open http://localhost:8080
    elif command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:8080
    else
        echo "Please open http://localhost:8080 in your browser"
    fi
}

function show_help() {
    cat << EOF
Kafka Cluster Management Script - Production Version

Usage: $0 <command> [options]

CLUSTER MANAGEMENT:
  init                          - Initialize cluster (generate ID and format storage)
  start                         - Start Kafka cluster
  stop                          - Stop Kafka cluster
  restart                       - Restart Kafka cluster
  status                        - Show cluster status
  health                        - Run health checks
  logs <node> [lines]          - View logs (default: kafka1, 100 lines)
  info                          - Show cluster information
  backup                        - Backup configurations

TOPIC MANAGEMENT:
  create-topic <name> [p] [r]  - Create topic (p=partitions, r=replication)
  delete-topic <name>           - Delete topic
  list-topics                   - List all topics
  describe-topic <name>         - Describe specific topic
  alter-topic <name> <key> <v> - Alter topic configuration

MESSAGING:
  produce <topic>               - Produce messages to topic
  consume <topic> [from-beginning] - Consume messages from topic

CONSUMER GROUPS:
  list-groups                   - List all consumer groups
  describe-group <name>         - Describe consumer group

UTILITIES:
  ui                            - Open Kafka UI in browser
  help                          - Show this help message

EXAMPLES:
  $0 init                                    # First-time setup
  $0 start                                   # Start cluster
  $0 create-topic orders 6 3                # Create topic with 6 partitions, RF=3
  $0 alter-topic orders retention.ms 604800000  # Set 7-day retention
  $0 produce orders                          # Send messages
  $0 consume orders from-beginning          # Read all messages
  $0 logs kafka1 500                        # View last 500 log lines
  $0 health                                  # Check cluster health

EOF
}

# Main command handler
case "$1" in
    init)
        check_prerequisites
        generate_cluster_id
        format_storage
        echo ""
        print_success "Cluster initialized successfully!"
        echo "Next step: Run '$0 start' to start the cluster"
        ;;
    start)
        start_kafka
        ;;
    stop)
        stop_kafka
        ;;
    restart)
        restart_kafka
        ;;
    status)
        check_status
        ;;
    health)
        check_health
        ;;
    logs)
        view_logs "$@"
        ;;
    create-topic)
        create_topic "$@"
        ;;
    delete-topic)
        delete_topic "$@"
        ;;
    list-topics)
        list_topics
        ;;
    describe-topic)
        describe_topic "$@"
        ;;
    alter-topic)
        alter_topic "$@"
        ;;
    produce)
        produce_message "$@"
        ;;
    consume)
        consume_messages "$@"
        ;;
    info)
        cluster_info
        ;;
    list-groups)
        list_consumer_groups
        ;;
    describe-group)
        describe_consumer_group "$@"
        ;;
    backup)
        backup_config
        ;;
    ui)
        open_ui
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_help
        exit 1
        ;;
esac
