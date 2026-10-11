#!/bin/sh
# ==============================================================================
# Bai 4: Custom Network & Named Volume bang Docker CLI
# Mon ta: Noi 2 container (Backend + PostgreSQL) qua custom bridge network
#         app-net, luu tru ben vung bang named volume db-data.
# Cach chay (Git Bash / WSL / Linux / macOS):
#   chmod +x commands.sh
#   ./commands.sh
# Cach chay (Windows PowerShell - neu chua co bash, chay tung lenh thu cong):
#   bash commands.sh
# ==============================================================================

set -eu

# ---- Bien cau hinh (doi o day neu muon) ----
NETWORK="app-net"
VOLUME="db-data"
DB_CONTAINER="db-server"
BACKEND_CONTAINER="app-container"
POSTGRES_IMAGE="postgres:15-alpine"
BACKEND_IMAGE="alpine:latest"
POSTGRES_USER="appuser"
POSTGRES_PASSWORD="supersecret123"
POSTGRES_DB="appdb"

echo "=== [1/7] Tao Custom Bridge Network: $NETWORK ==="
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK}$"; then
  echo "-> Network '$NETWORK' da ton tai, bo qua."
else
  docker network create --driver bridge "$NETWORK"
fi
docker network ls | grep "$NETWORK" || true

echo ""
echo "=== [2/7] Tao Named Volume: $VOLUME ==="
if docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME}$"; then
  echo "-> Volume '$VOLUME' da ton tai, bo qua."
else
  docker volume create "$VOLUME"
fi
docker volume ls | grep "$VOLUME" || true

echo ""
echo "=== [3/7] Don dep container cu (neu co) ==="
docker rm -f "$DB_CONTAINER" "$BACKEND_CONTAINER" 2>/dev/null || true

echo ""
echo "=== [4/7] Khoi chay Database Container ($POSTGRES_IMAGE) ==="
docker run -d \
  --name "$DB_CONTAINER" \
  --network "$NETWORK" \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  "$POSTGRES_IMAGE"

echo "-> Cho PostgreSQL san sang (pg_isready)..."
# Cho toi da ~60s
for i in $(seq 1 30); do
  if docker exec "$DB_CONTAINER" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    echo "-> DB san sang sau ${i}x2s."
    break
  fi
  echo "   doi 2s... ($i/30)"
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "LOI: DB khong san sang. Xem logs:"
    docker logs "$DB_CONTAINER" | tail -n 50
    exit 1
  fi
done

echo ""
echo "=== [5/7] Khoi chay Backend Container (tham gia $NETWORK) ==="
# Dung alpine nhe, giu container chay nen + co san ping (busybox).
# Truyen bien ket noi DB bang hostname db-server (DNS noi bo cua Docker).
docker run -d \
  --name "$BACKEND_CONTAINER" \
  --network "$NETWORK" \
  -e DB_HOST="$DB_CONTAINER" \
  -e DB_PORT=5432 \
  -e DB_NAME="$POSTGRES_DB" \
  -e DB_USER="$POSTGRES_USER" \
  -e DB_PASSWORD="$POSTGRES_PASSWORD" \
  "$BACKEND_IMAGE" \
  tail -f /dev/null

echo "-> Backend env:"
docker exec "$BACKEND_CONTAINER" env | grep DB_ || true

echo ""
echo "=== [6/7] Kiem tra DNS noi bo: ping db-server tu backend ==="
docker exec "$BACKEND_CONTAINER" ping -c 2 "$DB_CONTAINER"

echo ""
echo "-> Thong tin network (inspect):"
docker network inspect "$NETWORK"

echo ""
echo "=== [7/7] Test Data Persistence ==="
echo "-> [7a] Tao bang + chen du lieu mau:"
docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "CREATE TABLE IF NOT EXISTS persistence_test (id SERIAL PRIMARY KEY, msg TEXT, created_at TIMESTAMPTZ DEFAULT now());"
docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "INSERT INTO persistence_test (msg) VALUES ('hello-persistence-bai4');"
echo "-> Du lieu TRUOC khi xoa container:"
docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT * FROM persistence_test ORDER BY id DESC LIMIT 5;"

echo ""
echo "-> [7b] Xoa CUNG container DB (mo phong mat container, volume van giu lai):"
docker rm -f "$DB_CONTAINER"
echo "-> Kiem tra volume van con:"
docker volume ls | grep "$VOLUME"

echo ""
echo "-> [7c] Khoi chay lai container DB MOI, gan cung volume $VOLUME:"
docker run -d \
  --name "$DB_CONTAINER" \
  --network "$NETWORK" \
  -v "${VOLUME}:/var/lib/postgresql/data" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  "$POSTGRES_IMAGE"

echo "-> Cho DB hoi sinh..."
for i in $(seq 1 30); do
  if docker exec "$DB_CONTAINER" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    echo "-> DB hoi sinh sau ${i}x2s."
    break
  fi
  echo "   doi 2s... ($i/30)"
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "LOI: DB moi khong san sang."
    docker logs "$DB_CONTAINER" | tail -n 50
    exit 1
  fi
done

echo "-> Du lieu SAU khi tai tao container (phai con nguyen):"
docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT * FROM persistence_test ORDER BY id DESC LIMIT 5;"
COUNT=$(docker exec "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM persistence_test;")
echo "-> Tong so dong: $COUNT"
if [ "${COUNT:-0}" -ge 1 ]; then
  echo "THANH CONG: Du lieu van con sau khi rm -f + recreate (volume $VOLUME hoat dong)."
else
  echo "THAT BAI: Mat du lieu!"
  exit 1
fi

echo ""
echo "=============================================================================="
echo "HOAN TAT BAI 4"
echo "Kiem tra nhanh:"
echo "  docker network ls | grep $NETWORK"
echo "  docker volume ls | grep $VOLUME"
echo "  docker network inspect $NETWORK"
echo "  docker exec -it $BACKEND_CONTAINER ping -c 2 $DB_CONTAINER"
echo "  docker exec -it $DB_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c 'SELECT * FROM persistence_test;'"
echo "Don dep (neu muon):"
echo "  docker rm -f $BACKEND_CONTAINER $DB_CONTAINER"
echo "  docker network rm $NETWORK"
echo "  docker volume rm $VOLUME   # CAN THANH: xoa volume se MAT du lieu!"
echo "=============================================================================="
