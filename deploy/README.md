# Deploying FoodOnTheGo to techpio.tech

A review deployment on the Hostinger VPS at `93.188.167.45`, served at
**techpio.tech**. `piodesk.com` and whatever serves it are not touched by any
step here.

## What this deployment is not

Read this before showing the result to anybody.

**It is not production, and it cannot be.** `ProductionConfigGuard` refuses to
boot in `staging` or `production` without a real SMS vendor, Google Places,
Google Routes and Razorpay credentials. None exist for this project, and none
were invented. So this runs as `APP_ENV=review`, where the guard stands aside.

What that costs, precisely:

| Area | What you get | What it means |
| --- | --- | --- |
| Sign-in | OTP codes written to `storage/logs` | Anyone who can read that file can sign in as any customer who requested a code. Test accounts only. |
| Place search | A small fixed gazetteer | Most real addresses will not be found. |
| **Routing** | **Straight lines between points** | **Distances and durations are arithmetic, not roads.** This is the one most likely to mislead a viewer, because it looks like a real answer. |
| Payment | Refuses every call | Checkout works up to the point of paying and then stops, correctly. |
| Orders | Real | An order is placed and sits `AWAITING_PAYMENT`. |

Everything else — discovery along a route, search and filters, menus,
customisation, the cart, pickup times, the priced checkout, tenant isolation —
is the real implementation against a real database.

## Step 0 — find out what is already on the box

Read-only. Nothing here changes anything. Run it and read the output before
going further.

```bash
ss -tlnp | grep -E ':(80|443)\s' || echo 'nothing is listening on 80/443'
command -v docker >/dev/null && docker ps --format '{{.Names}}\t{{.Ports}}' || echo 'no docker'
ls /etc/nginx/sites-enabled/ 2>/dev/null || echo 'no nginx sites-enabled'
```

- **Something already owns 80/443** (nginx serving piodesk.com, or a Docker
  proxy): good, that is what this is designed for. Continue.
- **Nothing owns them**: install nginx first — `apt update && apt install -y nginx certbot python3-certbot-nginx`.
- **Coolify, Dokploy, Traefik or similar**: do not add the nginx vhost in step
  4. Point that proxy at `127.0.0.1:8090` instead and skip to step 6.

## Step 1 — DNS

Point techpio.tech at the box, then wait for it to resolve before step 5.
Certbot cannot issue a certificate for a name that does not yet point here.

```
A    techpio.tech        93.188.167.45
A    www.techpio.tech    93.188.167.45
```

```bash
dig +short techpio.tech    # must print 93.188.167.45
```

## Step 2 — get the code

```bash
mkdir -p /opt && cd /opt
git clone -b claude/foodonthego-s0x2vt https://github.com/Dalbeirdev/foodonthego.git foodonthego
cd /opt/foodonthego/deploy
```

## Step 3 — configure

```bash
cp .env.example .env
openssl rand -base64 24   # DB_PASSWORD
openssl rand -base64 24   # DB_ROOT_PASSWORD
nano .env
```

`APP_KEY` needs Laravel to generate it. Easiest, once the stack is up:

```bash
docker compose run --rm php php artisan key:generate --show
# paste the base64:... value into .env, then continue
```

## Step 4 — the vhost

Only if the host runs nginx directly. **This adds a file. It edits nothing.**

```bash
cp nginx/techpio.tech.conf /etc/nginx/sites-available/techpio.tech
ln -s /etc/nginx/sites-available/techpio.tech /etc/nginx/sites-enabled/techpio.tech
nginx -t          # must say "test is successful" — if not, do NOT reload
systemctl reload nginx
```

`nginx -t` before reloading is not ceremony: a reload with a bad config on a
box that is also serving piodesk.com is how one deployment takes down two
sites.

## Step 5 — TLS

```bash
certbot --nginx -d techpio.tech -d www.techpio.tech
```

Certbot edits the vhost from step 4 and leaves other vhosts alone. Renewal is
installed as a timer; check it with `systemctl list-timers | grep certbot`.

## Step 6 — build and start

The first build is slow — it compiles the Flutter web app and both React
shells — and wants roughly 4 GB of free disk. `df -h /` first.

```bash
cd /opt/foodonthego/deploy
docker compose build
docker compose up -d
docker compose run --rm php php artisan migrate --force
```

## Step 7 — check it, from the server and from outside

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/api/v1/health/live
curl -sS -o /dev/null -w '%{http_code}\n' https://techpio.tech/
```

Then open `https://techpio.tech` in a browser. The customer app is at the root,
the restaurant shell at `/restaurant`, the admin shell at `/admin`.

**Confirm piodesk.com still works** before you call this done. That is the one
check this whole design exists to protect.

## Updating after new commits

```bash
cd /opt/foodonthego && git pull
cd deploy && docker compose build && docker compose up -d
docker compose run --rm php php artisan migrate --force
```

## Getting the OTP code, since no SMS is sent

```bash
docker compose exec php sh -c 'tail -n 20 storage/logs/otp-development.log'
```

## Moving to real credentials later

Fill in the provider blocks in `.env`, set `APP_ENV=production`, and restart.
The guard will refuse to boot and name anything still missing — that refusal is
the feature. Do not work around it by returning `APP_ENV` to `review`; that
turns a loud missing integration into a quiet one.

## Security notes for this box

- Root SSH with a password on a public IP is brute-forced continuously. Use a
  key, set `PermitRootLogin prohibit-password`, and consider fail2ban.
- Nothing in this stack publishes a public port. MySQL and Redis are reachable
  only from the compose network; the app is on `127.0.0.1:8090`. Keep it that
  way — `ports: 3306:3306` on the database would expose it to the internet.
- `deploy/.env` holds the database passwords and is gitignored. It is not in
  the repository and must not be committed.
