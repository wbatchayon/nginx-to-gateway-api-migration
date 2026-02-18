#!/bin/bash
# Load Tests - Tests de performance pour Gateway API vs NGINX Ingress

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration par défaut
DURATION="1m"
RPS=100
ENDPOINT_GATEWAY="http://app-v2.demo.local"
ENDPOINT_NGINX="http://app-v1.demo.local"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --rps)
            RPS="$2"
            shift 2
            ;;
        --gateway-only)
            ENDPOINT_NGINX=""
            shift
            ;;
        --nginx-only)
            ENDPOINT_GATEWAY=""
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Load Tests Configuration:${NC}"
echo "Duration: $DURATION"
echo "RPS: $RPS"
echo "Gateway Endpoint: $ENDPOINT_GATEWAY"
echo "NGINX Endpoint: $ENDPOINT_NGINX"
echo ""

# Fonction pour exécuter le test de charge
run_load_test() {
    local name=$1
    local endpoint=$2
    local duration=$3
    local rps=$4
    
    echo -e "${BLUE}Running load test: $name${NC}"
    echo "Endpoint: $endpoint"
    echo "Duration: $duration"
    echo "RPS: $rps"
    echo ""
    
    # Vérifier si le point d'accès est accessible
    if ! curl -s -m 5 "$endpoint" >/dev/null 2>&1; then
        echo -e "${RED}Endpoint $endpoint not accessible!${NC}"
        return 1
    fi
    
    # Exécuter le test de charge avec ab (Apache Bench)
    if command -v ab >/dev/null 2>&1; then
        # Calculer le nombre total de requ\u00eates en fonction de la dur\u00e9e
        # Ceci est approximatif - ajustez selon les besoins
        TOTAL_REQUESTS=$((RPS * 60))  # Assuming duration in seconds
        
        echo "Starting load test with Apache Bench..."
        ab -n $TOTAL_REQUESTS -c $RPS "$endpoint/" 2>&1 | tee "/tmp/loadtest_${name}_$(date +%s).log"
        
    # Secours vers Apache Bench via Docker si disponible
    elif command -v docker >/dev/null 2>&1; then
        echo "Running load test with Docker (httpd image)..."
        docker run --rm -it httpd:latest ab -n 10000 -c $RPS "$endpoint/" 2>&1
        
    # Secours vers wrk si disponible
    elif command -v wrk >/dev/null 2>&1; then
        echo "Running load test with wrk..."
        wrk -t 4 -c $RPS -d $DURATION "$endpoint/" 2>&1
        
    # Secours vers curl en boucle
    else
        echo "Running load test with curl (limited)..."
        START=$(date +%s)
        END=$((START + 60))
        COUNT=0
        
        while [ $(date +%s) -lt $END ]; do
            curl -s "$endpoint/" >/dev/null 2>&1 &
            ((COUNT++))
            if [ $((COUNT % 50)) -eq 0 ]; then
                echo "  Requests sent: $COUNT"
            fi
        done
        
        echo -e "${GREEN}Load test completed: $COUNT requests${NC}"
    fi
}

# Exécuter les tests
if [ ! -z "$ENDPOINT_GATEWAY" ]; then
    echo ""
    echo -e "${BLUE}=== Gateway API Load Test ===${NC}"
    run_load_test "gateway-api" "$ENDPOINT_GATEWAY" "$DURATION" "$RPS"
fi

if [ ! -z "$ENDPOINT_NGINX" ]; then
    echo ""
    echo -e "${BLUE}=== NGINX Ingress Load Test ===${NC}"
    run_load_test "nginx-ingress" "$ENDPOINT_NGINX" "$DURATION" "$RPS"
fi

echo ""
echo -e "${GREEN}Load tests completed!${NC}"
echo ""
echo "Results saved to: /tmp/loadtest_*.log"
echo ""
echo "Analyze results with:"
echo "  - Prometheus queries"
echo "  - Grafana dashboards"
echo "  - kubectl logs"
