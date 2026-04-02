#!/bin/bash
# Stream a video file as an RTSP feed for Helios GCS testing.
#
# Usage:
#   ./scripts/sim_video.sh [video_file]
#
# If no video file is provided, generates a synthetic test pattern.
# Requires: ffmpeg + mediamtx (make install-sim-deps)
#
# Connect in Helios: Video tab → rtsp://127.0.0.1:8554/stream

set -e

PORT=8554
STREAM_URL="rtsp://127.0.0.1:$PORT/stream"
VIDEO_FILE="${1:-}"

if ! command -v ffmpeg &> /dev/null; then
  echo "Error: ffmpeg required. Run: make install-sim-deps"
  exit 1
fi

if ! command -v mediamtx &> /dev/null; then
  echo "Error: mediamtx required. Run: make install-sim-deps"
  exit 1
fi

# Kill any existing mediamtx on the port
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true

echo "Helios Video Simulator"
echo "======================"

# Start mediamtx RTSP server with config that allows any path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mediamtx "$SCRIPT_DIR/mediamtx.yml" &> /tmp/mediamtx.log &
MEDIAMTX_PID=$!

cleanup() {
  kill $MEDIAMTX_PID 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM EXIT

# Wait for mediamtx to be ready
for i in $(seq 1 10); do
  if lsof -i:$PORT -sTCP:LISTEN &>/dev/null; then
    break
  fi
  sleep 0.5
done

if ! lsof -i:$PORT -sTCP:LISTEN &>/dev/null; then
  echo "Error: mediamtx failed to start. Check /tmp/mediamtx.log"
  exit 1
fi

echo "Stream URL: $STREAM_URL"
echo ""

if [ -z "$VIDEO_FILE" ]; then
  echo "Streaming: synthetic test pattern"
  echo "Press Ctrl+C to stop"
  echo ""

  ffmpeg -re -f lavfi \
    -i "testsrc2=size=1280x720:rate=30" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -rtsp_transport tcp \
    -f rtsp "$STREAM_URL"
else
  if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: File not found: $VIDEO_FILE"
    exit 1
  fi

  echo "Streaming: $VIDEO_FILE (looping)"
  echo "Press Ctrl+C to stop"
  echo ""

  ffmpeg -re -stream_loop -1 -i "$VIDEO_FILE" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -an \
    -rtsp_transport tcp \
    -f rtsp "$STREAM_URL"
fi
