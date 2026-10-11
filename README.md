# Bài 4: Custom Network & Named Volume bằng Docker CLI

## 1. Mục tiêu
- Tạo **Custom Bridge Network** `app-net` để các container giao tiếp nội bộ qua **tên service (DNS resolution)**.
- Tạo **Named Volume** `db-data` để lưu dữ liệu PostgreSQL bền vững, sống sót sau khi xóa container.
- Kết nối cụm 2 container: **Backend Web API (`app-container`) + PostgreSQL (`db-server`)** hoàn toàn bằng Docker CLI thủ công.

## 2. Kiến trúc

```
                  ┌──────────────────────── app-net (bridge) ────────────────────────┐
                  │                                                                   │
  ┌───────────────┴───────────────┐                              ┌────────────────────┴────────────┐
  │ app-container (alpine:latest) │  ── ping / DNS ──▶ db-server │ db-server (postgres:15-alpine)  │
  │  env: DB_HOST=db-server       │                              │  mount: db-data ➜ /var/lib/...  │
  │       DB_PORT=5432            │                              │  env: POSTGRES_USER/DB/PASSWORD │
  └───────────────────────────────┘                              └─────────────────────────────────┘
                                                                              │
                                                                     ┌────────┴────────┐
                                                                     │ db-data (volume)│
                                                                     │  PERSISTENT     │
                                                                     └─────────────────┘
```

- `app-net`: bridge network riêng, Docker Embedded DNS tự phân giải `db-server` → IP nội bộ (vd `172.18.0.2`).
- `db-data`: named volume, mount vào `/var/lib/postgresql/data` (đường dẫn data chuẩn của Postgres).

## 3. Nộp bài
| File | Mô tả |
|------|-------|
| `commands.sh` | Script thực thi toàn bộ thao tác (tạo net/volume, run DB + backend, ping, test persistence) |
| `README.md` | File này — giải thích + hướng dẫn kiểm tra |

## 4. Cách chạy

### Yêu cầu
- Docker Engine + Docker CLI (đã test với Docker `29.x`).
- Bash: Git Bash / WSL / Linux / macOS. Nếu dùng PowerShell thuần, chạy `bash commands.sh`.

### Chạy 1 lệnh duy nhất
```bash
cd bai4
chmod +x commands.sh
./commands.sh
# hoặc: bash commands.sh
```

Script tự:
1. Tạo network `app-net` (bỏ qua nếu đã tồn tại).
2. Tạo volume `db-data`.
3. Xóa container cũ `db-server`, `app-container` nếu còn.
4. `docker run -d --name db-server --network app-net -v db-data:/var/lib/postgresql/data -e POSTGRES_* postgres:15-alpine`.
5. Chờ `pg_isready` tối đa ~60s.
6. `docker run -d --name app-container --network app-net -e DB_HOST=db-server alpine tail -f /dev/null`.
7. `docker exec app-container ping -c 2 db-server`.
8. Test persistence: `CREATE TABLE + INSERT` → `docker rm -f db-server` → run lại container mới cùng volume → `SELECT` xác minh.

### Chạy thủ công từng bước (để học / demo)
```bash
docker network create --driver bridge app-net
docker volume create db-data

docker run -d --name db-server --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=appuser -e POSTGRES_PASSWORD=supersecret123 -e POSTGRES_DB=appdb \
  postgres:15-alpine

docker run -d --name app-container --network app-net \
  -e DB_HOST=db-server -e DB_PORT=5432 \
  alpine tail -f /dev/null

docker exec app-container ping -c 2 db-server
```

## 5. Kiểm tra (theo đề bài)

```bash
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net
docker exec -it app-container ping -c 2 db-server

# Kiểm tra dữ liệu còn sau recreate:
docker exec -it db-server psql -U appuser -d appdb -c "SELECT * FROM persistence_test;"
```

Kết quả mong đợi:
- `ping db-server` từ `app-container` **phân giải thành công** ra IP nội bộ, ví dụ:
  ```
  PING db-server (172.18.0.2): 56 data bytes
  64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.2 ms
  ```
- `docker network inspect app-net` thấy 2 container trong mục `Containers`.
- Sau `docker rm -f db-server` + run lại cùng `db-data`, `SELECT * FROM persistence_test` vẫn trả về dòng `hello-persistence-bai4` → **dữ liệu nguyên vẹn**.

## 6. Giải thích lệnh mount Postgres
```
-v db-data:/var/lib/postgresql/data
```
- Vế trái `db-data`: tên named volume do Docker quản lý (`/var/lib/docker/volumes/db-data`).
- Vế phải `/var/lib/postgresql/data`: nơi image `postgres` ghi toàn bộ WAL + table files.
- Khi `rm -f` container, volume **không bị xóa** → container mới mount lại volume cũ là đọc được data cũ.

## 7. Dọn dẹp
```bash
docker rm -f app-container db-server
docker network rm app-net
docker volume rm db-data   # CẨN THẬN: mất hết dữ liệu test!
```

## 8. Lỗi thường gặp
| Lỗi | Nguyên nhân → Cách sửa |
|-----|------------------------|
| `password authentication failed` | Sai `POSTGRES_PASSWORD` khi recreate → phải dùng đúng password cũ, vì data dir đã init với password đầu tiên |
| `database files are incompatible` | Đổi tag image Postgres khác major version mà giữ volume cũ → xóa volume hoặc giữ nguyên `15-alpine` |
| `ping: bad address 'db-server'` | 2 container khác network → kiểm tra `docker network inspect app-net` và `--network app-net` khi run |
| `pg_isready: could not connect` | DB chưa khởi động xong → chờ thêm, xem `docker logs db-server` |
