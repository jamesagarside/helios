#!/usr/bin/env bash
##
## Start ArduPilot SITL for Helios GCS development.
##
## Usage:
##   ./scripts/start-sitl.sh              # ArduPlane (default)
##   ./scripts/start-sitl.sh copter        # ArduCopter
##   ./scripts/start-sitl.sh plane 5       # ArduPlane at 5x speed
##
## Prerequisites: Docker running
##
## MAVLink output:
##   UDP → localhost:14550 (connect Helios here)
##   TCP → localhost:5760  (alternative)
##

set -euo pipefail

VEHICLE="${1:-ArduPlane}"
SPEEDUP="${2:-1}"

case "$VEHICLE" in
  copter|ArduCopter)
    VEHICLE="ArduCopter"
    FRAME="quad"
    ;;
  plane|ArduPlane)
    VEHICLE="ArduPlane"
    FRAME="plane"
    ;;
  rover|Rover)
    VEHICLE="Rover"
    FRAME="rover"
    ;;
  *)
    echo "Unknown vehicle: $VEHICLE"
    echo "Options: plane, copter, rover"
    exit 1
    ;;
esac

echo "Starting $VEHICLE SITL (frame=$FRAME, speedup=${SPEEDUP}x)..."
echo "MAVLink will be available at:"
echo "  UDP: localhost:14550"
echo "  TCP: localhost:5760"
echo ""
echo "Press Ctrl+C to stop."
echo ""

VEHICLE="$VEHICLE" FRAME="$FRAME" SPEEDUP="$SPEEDUP" \
  docker compose -f docker/docker-compose.sitl.yaml up --pull missing
