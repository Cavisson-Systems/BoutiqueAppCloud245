#!/bin/bash

NAMESPACE="boutique"

ALL_SERVICES=(
  adservice
  cartservice
  checkoutservice
  currencyservice
  emailservice
  frontend
  paymentservice
  productcatalogservice
  recommendationservice
  shippingservice
  loadgenerator
  redis-cart
)

echo "Available services:"
echo "--------------------------------"
for SERVICE in "${ALL_SERVICES[@]}"
do
    echo "$SERVICE"
done
echo "--------------------------------"

read -p "Enter services to scale down (space separated or 'all'): " INPUT_SERVICES

read -p "Enter replica count: " REPLICAS

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]
then
    echo "Invalid replica count: $REPLICAS"
    exit 1
fi


if [ "$INPUT_SERVICES" == "all" ]
then
    SERVICES=("${ALL_SERVICES[@]}")
else
    SERVICES=($INPUT_SERVICES)
fi


echo ""
echo "Scaling following services to $REPLICAS replicas:"
echo "--------------------------------"

for SERVICE in "${SERVICES[@]}"
do
    echo "$SERVICE"
done

echo "--------------------------------"


for SERVICE in "${SERVICES[@]}"
do
    echo "Scaling $SERVICE -> $REPLICAS"

    kubectl scale deployment "$SERVICE" \
      -n "$NAMESPACE" \
      --replicas="$REPLICAS"

    if [ $? -ne 0 ]
    then
        echo "Failed scaling $SERVICE"
    fi
done


echo ""
echo "===================================="
echo "Scaling completed"
echo "===================================="
