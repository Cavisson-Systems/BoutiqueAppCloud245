#!/bin/bash

NAMESPACE="boutique"

# Create namespace if it doesn't already exist
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || \
kubectl create namespace "$NAMESPACE"

echo "Namespace $NAMESPACE is ready."

#Apply all YAML files in the current directory
kubectl apply -f . 

STEP=5
WAIT=60

SERVICES=(
  adservice
  cartservice
  currencyservice
  emailservice
  productcatalogservice
  recommendationservice
  redis-cart
  shippingservice
  checkoutservice
  frontend
  paymentservice
)

declare -A TARGETS
TARGETS[checkoutservice]=1
TARGETS[frontend]=1
TARGETS[paymentservice]=1


print_status() {

    local SERVICE

    echo ""
    printf "%-25s %-10s %-12s %-25s\n" "SERVICE" "READY" "RESTARTS" "NODE"
    printf "%-25s %-10s %-12s %-25s\n" "-------------------------" "----------" "------------" "-------------------------"

    for SERVICE in "${SERVICES[@]}"
    do
        kubectl get pods \
          -n "$NAMESPACE" \
          -l app="$SERVICE" \
          -o json | \
        jq -r --arg svc "$SERVICE" '
        .items[] |
        [
          $svc,
          (
            ([.status.containerStatuses[]?.ready] | map(select(.==true)) | length)
            | tostring
          ) + "/" +
          (
            ([.status.containerStatuses[]?] | length)
            | tostring
          ),
          (
            [.status.containerStatuses[]?.restartCount]
            | add // 0
          ),
          .spec.nodeName
        ] | @tsv' |
        awk -F'\t' '{printf "%-25s %-10s %-12s %-25s\n",$1,$2,$3,$4}'
    done

    echo ""
}


show_pending_services() {

    local SERVICE
    local READY
    local EXPECTED

    echo "----------------------------------------------"
    echo "Waiting for:"
    echo ""

    for SERVICE in "${SERVICES[@]}"
    do

        READY=$(kubectl get pods \
          -n "$NAMESPACE" \
          -l app="$SERVICE" \
          -o json | \
          jq '[.items[].status.containerStatuses[0].ready] | map(select(.==true)) | length')


        EXPECTED=$(kubectl get deployment "$SERVICE" \
          -n "$NAMESPACE" \
          -o jsonpath='{.spec.replicas}')


        if [ "$READY" -ne "$EXPECTED" ]
        then

            echo "$SERVICE"
            echo "Expected : $EXPECTED replicas"
            echo "Ready    : $READY replicas"
            echo ""

            kubectl get pods \
              -n "$NAMESPACE" \
              -l app="$SERVICE" \
              -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.containerStatuses[0].ready,\
RESTARTS:.status.containerStatuses[0].restartCount,\
NODE:.spec.nodeName

            echo ""
        fi

    done

    echo "Retrying after ${WAIT}s..."
    echo "----------------------------------------------"
}


wait_for_ready() {

    local SERVICE
    local READY
    local EXPECTED
    local ALL_READY

    echo ""
    echo "=============================================="
    echo "Waiting for deployments to become Ready"
    echo "=============================================="

    while true
    do

        print_status

        ALL_READY=true


        for SERVICE in "${SERVICES[@]}"
        do

            READY=$(kubectl get pods \
              -n "$NAMESPACE" \
              -l app="$SERVICE" \
              -o json | \
              jq '[.items[].status.containerStatuses[0].ready] | map(select(.==true)) | length')


            EXPECTED=$(kubectl get deployment "$SERVICE" \
              -n "$NAMESPACE" \
              -o jsonpath='{.spec.replicas}')


            if [ "$READY" -ne "$EXPECTED" ]
            then
                ALL_READY=false
                break
            fi

        done


        if [ "$ALL_READY" = true ]
        then
            echo "All services are Ready"
            break
        fi


        show_pending_services

        sleep "$WAIT"

    done
}



wait_for_service() {

    local SERVICE=$1
    local TARGET=$2
    local READY

    while true
    do

        READY=$(kubectl get pods \
          -n "$NAMESPACE" \
          -l app="$SERVICE" \
          -o json | \
          jq '[.items[].status.containerStatuses[0].ready] | map(select(.==true)) | length')


        if [ "$READY" -eq "$TARGET" ]
        then
            echo "$SERVICE reached $TARGET replicas"
            break
        fi


        echo ""
        echo "Waiting for: $SERVICE"
        echo "Expected : $TARGET replicas"
        echo "Ready    : $READY replicas"
        echo ""

        kubectl get pods \
          -n "$NAMESPACE" \
          -l app="$SERVICE" \
          -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.containerStatuses[0].ready,\
RESTARTS:.status.containerStatuses[0].restartCount,\
NODE:.spec.nodeName


        sleep "$WAIT"

    done
}



echo "=============================================="
echo "Starting all deployments"
echo "=============================================="


for SERVICE in "${SERVICES[@]}"
do
    echo "Starting $SERVICE"

    kubectl scale deployment "$SERVICE" \
      -n "$NAMESPACE" \
      --replicas=1
done



wait_for_ready



echo ""
echo "=============================================="
echo "Starting gradual scale-up"
echo "=============================================="


for SERVICE in "${!TARGETS[@]}"
do

    TARGET=${TARGETS[$SERVICE]}
    CURRENT=1


    echo ""
    echo "Scaling $SERVICE to $TARGET replicas"


    while [ "$CURRENT" -lt "$TARGET" ]
    do

        NEXT=$((CURRENT + STEP))


        if [ "$NEXT" -gt "$TARGET" ]
        then
            NEXT=$TARGET
        fi


        echo ""
        echo "$SERVICE : $CURRENT -> $NEXT"


        kubectl scale deployment "$SERVICE" \
          -n "$NAMESPACE" \
          --replicas="$NEXT"


        wait_for_service "$SERVICE" "$NEXT"


        CURRENT=$NEXT


        print_status

    done

done


echo ""
echo "=============================================="
echo "Scaling completed successfully"
echo "=============================================="


print_status
