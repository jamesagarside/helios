#!/usr/bin/env bash
##
## Start a test RTSP video stream for Helios GCS development.
##
## Usage:
##   ./scripts/test_video_stream.sh
##
## Requires: ffmpeg (brew install ffmpeg)
##
## Generates a test pattern video and streams it via RTSP on:
##   rtsp://127.0.0.1:8554/stream
##
## Connect Helios Video tab with: rtsp://127.0.0.1:8554/stream
##

set -euo pipefail

# Check dependencies
if ! command -v ffmpeg &>/dev/null; then
  echo "ffmpeg not found. Install with: brew install ffmpeg"
  exit 1
fi

PORT="${1:-8554}"
echo "Starting test RTSP video stream..."
echo "  URL: rtsp://127.0.0.1:$PORT/stream"
echo "  Set this URL in Helios > Setup > Video Stream"
echo ""
echo "Press Ctrl+C to stop."
echo ""

# Generate a test pattern and stream via RTP/RTSP
# Using UDP as a simple test — sends raw H.264 over UDP
# For a proper RTSP server, use mediamtx (formerly rtsp-simple-server)

# Option 1: Simple UDP stream (works with media_kit)
ffmpeg -re \
  -f lavfi -i "testsrc2=size=1280x720:rate=30,drawtext=text='HELIOS TEST STREAM %{localtime}':fontsize=36:fontcolor=white:x=10:y=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -b:v 2M -g 30 \
  -c:a aac -b:a 128k \
  -f rtsp \
  "rtsp://127.0.0.1:$PORT/stream" \
  2>&1 || {
    echo ""
    echo "ffmpeg RTSP output requires an RTSP server."
    echo "Install mediamtx for a proper RTSP server:"
    echo "  brew install mediamtx"
    echo "  mediamtx &"
    echo "  Then re-run this script."
    echo ""
    echo "Alternative: Using raw UDP stream instead..."
    echo "  URL: udp://127.0.0.1:$PORT"
    ffmpeg -re \
      -f lavfi -i "testsrc2=size=1280x720:rate=30,drawtext=text='HELIOS TEST %{localtime}':fontsize=36:fontcolor=white:x=10:y=10" \
      -c:v libx264 -preset ultrafast -tune zerolatency \
      -b:v 2M \
      -f mpegts \
      "udp://127.0.0.1:$PORT"
  }
