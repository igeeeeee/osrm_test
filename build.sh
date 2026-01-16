#!/usr/bin/env bash
set -euo pipefail

# ===== Helpers =====
msg() { echo -e "\n[build.sh] $*\n"; }

need_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo "[ERROR] Missing file: $f" >&2
    exit 1
  fi
}

# ===== Config =====
OSRM_IMAGE="ghcr.io/project-osrm/osrm-backend:v5.27.1"
OSMIUM_IMAGE="stefda/osmium-tool"

IN_PBF="input/kanto-latest.osm.pbf"
POLY="poly/kanto_mainland_only.poly"

# output
CLIP_PBF="extract/kanto_mainland.osm.pbf"
OSRM_BASENAME="kanto_mainland"   # -> extract/kanto_mainland.osrm*

mkdir -p input poly extract

# auto-download input PBF if missing
if [ ! -f "$IN_PBF" ]; then
  msg "Downloading kanto-latest.osm.pbf from Geofabrik..."
  wget -O "$IN_PBF" \
    https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf
fi

# ===== Main =====
msg "Checking inputs..."
need_file "$IN_PBF"
need_file "$POLY"

msg "Pulling Docker images..."
docker pull "$OSRM_IMAGE" >/dev/null
docker pull "$OSMIUM_IMAGE" >/dev/null

msg "Step 1/3: Clip PBF by polygon (osmium extract)"
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$PWD:/wkd" -w /wkd \
  "$OSMIUM_IMAGE" \
  osmium extract -p "$POLY" -s smart \
  -o "$CLIP_PBF" \
  "$IN_PBF"

if [ ! -f "$CLIP_PBF" ]; then
  echo "[ERROR] Clip PBF was not created: $CLIP_PBF" >&2
  exit 1
fi
ls -lh "$CLIP_PBF" || true

msg "Step 2/3: OSRM preprocessing (extract -> partition -> customize) with MLD"
docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  bash -lc "cd /data/extract && osrm-extract -p /opt/car.lua /data/$CLIP_PBF"

# if [ ! -f "extract/${OSRM_BASENAME}.osrm" ]; then
#   echo "[ERROR] Base OSRM file not found: extract/${OSRM_BASENAME}.osrm" >&2
#   echo "        Check osrm-extract logs above." >&2
#   exit 1
# fi

docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-partition "/data/extract/${OSRM_BASENAME}.osrm"

docker run --rm -t -v "$PWD:/data" "$OSRM_IMAGE" \
  osrm-customize "/data/extract/${OSRM_BASENAME}.osrm"

msg "Step 3/3: Final sanity checks"
# ls -lh "extract/${OSRM_BASENAME}.osrm" || true

for f in \
  "extract/${OSRM_BASENAME}.osrm.partition" \
  "extract/${OSRM_BASENAME}.osrm.cells"
do
  if [ ! -f "$f" ]; then
    echo "[ERROR] Missing required MLD file: $f" >&2
    exit 1
  fi
done

msg "Build completed successfully!"
cat << EOF
Next, run the server:

  docker run --rm -it -p 5000:5000 -v "\$PWD:/data" $OSRM_IMAGE \\
    osrm-routed --algorithm mld /data/extract/${OSRM_BASENAME}.osrm

Quick test (in another terminal):

  curl "http://localhost:5000/nearest/v1/driving/139.7670,35.6814?number=1"
EOF
