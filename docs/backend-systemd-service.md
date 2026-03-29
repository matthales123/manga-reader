# Backend Systemd Service

Run the FastAPI backend as a persistent background service so your terminal can be free.

## Install + Start (User Service)

From repo root:

```bash
cd /home/mhales/manga-reader
make backend-service-install
```

This creates:

`~/.config/systemd/user/manga-reader-backend.service`

Then it enables and starts it with `systemctl --user`.

## Common Commands

```bash
cd /home/mhales/manga-reader
make backend-service-status
make backend-service-restart
make backend-service-restart-clean
make backend-service-stop
make backend-service-logs
```

`backend-service-restart-clean` is useful if you accidentally started a manual backend process and got:
`address already in use` on port `8080`.

## Start At Boot / After Logout

To keep user services running even when you are not logged in:

```bash
sudo loginctl enable-linger $USER
```

## Service Behavior

- Uses `backend/run.sh` as `ExecStart`
- Loads environment from `backend/.env`
- Restarts automatically if it crashes (`Restart=always`)
- Avoid running `make backend-run` while the service is active.

## Verify From Phone

Open:

`http://<linux-server-ip>:8080/health`
