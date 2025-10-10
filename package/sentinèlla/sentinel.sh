#!/bin/dash

TOKEN=8448534574:AAEvsdQqhUDu3RVRJWDGIVeqRmXlB0Dqn1Q
CHAT_ID=380055934
POLLING_INTERVAL_SEC=${POLLING_INTERVAL_SEC:-3}

while true; do
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d text="your message"
done
