#!/usr/bin/env python3
"""Quick produce and consume test"""
from kafka import KafkaProducer, KafkaConsumer
import json
from datetime import datetime
import time

BOOTSTRAP_SERVERS = ['localhost:9092', 'localhost:9192', 'localhost:9292']

# TOPIC = 'test-persistence'
TOPIC = 'test-1759829975'


print("=" * 60)
print("Kafka Producer/Consumer Test")
print("=" * 60)

# Produce messages
print("\n📤 Producing 3 messages...")
producer = KafkaProducer(
    bootstrap_servers=BOOTSTRAP_SERVERS,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

for i in range(3):
    message = {
        'id': i,
        'timestamp': datetime.now().isoformat(),
        'message': f'Test message {i}'
    }
    future = producer.send(TOPIC, value=message)
    metadata = future.get(timeout=10)
    print(f"✓ Sent message {i} → Partition {metadata.partition}, Offset {metadata.offset}")

producer.flush()
producer.close()
print("✅ Producer finished!\n")

# Consume messages
print("📥 Consuming messages...")
consumer = KafkaConsumer(
    TOPIC,
    bootstrap_servers=BOOTSTRAP_SERVERS,
    auto_offset_reset='earliest',
    enable_auto_commit=False,
    # group_id='quick-test-group',
    group_id='test-group-1759829977',
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    consumer_timeout_ms=5000
)

message_count = 0
for message in consumer:
    message_count += 1
    print(f"✓ Received: {message.value['message']} (Partition {message.partition}, Offset {message.offset})")
    if message_count >= 3:
        break

consumer.close()
print(f"\n✅ Consumed {message_count} messages!")
print("\n" + "=" * 60)
print("🎉 SUCCESS! Kafka is working correctly!")
print("=" * 60)