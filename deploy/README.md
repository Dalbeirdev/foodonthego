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

**How it is published, on the box we have.** Not by nginx on the host — ports 80
and 443 belong to the nginx serving piodesk.com, and that application is not to
be touched. A Cloudflare Tunnel publishes it instead, binding no port and
contending for nothing. See step 4.

## The automated route (preferred)

`.github/workflows/deploy.yml` does everything below on every push, so the
steps that follow are the manual fallback and the explanation of what the
workflow is doing on your behalf.

### What you set, once

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | What it is |
| --- | --- |
| `DEPLOY_HOST` | `93.188.167.45` |
| `DEPLOY_USER` | the SSH user (`root`, or a user in the `docker` group) |
| `DEPLOY_SSH_KEY` | the **private** key, whole file including the BEGIN/END lines |
| `DEPLOY_KNOWN_HOSTS` | *optional but recommended* — output of `ssh-keyscan 93.188.167.45` |
| `DEPLOY_CERTBOT_EMAIL` | *optional* — where Let's Encrypt sends expiry warnings |

A non-standard SSH port goes in a **variable** (not a secret) called
`DEPLOY_PORT`.

Generate a key pair for this and nothing else:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/foodonthego_deploy -C 'github-actions deploy'
ssh-copy-id -i ~/.ssh/foodonthego_deploy.pub <user>@93.188.167.45
cat ~/.ssh/foodonthego_deploy        # this is DEPLOY_SSH_KEY
ssh-keyscan 93.188.167.45            # this is DEPLOY_KNOWN_HOSTS
```

The private key never passes through a chat window, an issue, or a commit. If
the secrets are absent the workflow **skips** rather than failing, so nothing
goes red before they are set.

### What it does

1. Packs `backend/ web/ mobile/ deploy/` — no `vendor`, `node_modules` or
   `build`, since the images rebuild them.
2. `scp`s it and unpacks to `/opt/foodonthego/releases/<sha>`.
3. On the **first** run only, generates `/opt/foodonthego/shared/.env` with a
   random `APP_KEY` and random database passwords. That file lives outside
   every release and survives all of them — **losing it makes the existing
   database unreadable**. Razorpay is left empty on purpose: `APP_ENV=review`
   is the only environment `ProductionConfigGuard` boots without real
   credentials, and a placeholder would defeat the guard.
4. `docker compose build && up -d`, then `migrate --force`, `config:cache`,
   `route:cache`.
5. Points `/opt/foodonthego/current` at the new release and prunes all but the
   last five.
6. **Proves it works** — polls `http://127.0.0.1:8090/api/v1/health/ready`
   until it answers 200, and dumps container logs and fails if it never does.
   A deploy that reports success because nothing threw is a deploy nobody has
   checked.

Rolling back is `ln -sfn` at an earlier release and `docker compose up -d` from
inside it.

### The one step that is opt-in

Installing the nginx vhost and requesting the certificate is the only thing
that goes near the server already serving **piodesk.com**, so it does not run
on a push. Trigger it deliberately: **Actions → Deploy — techpio.tech → Run
workflow → tick "Also install the techpio.tech vhost"**.

It refuses to proceed unless `techpio.tech` already resolves, runs `nginx -t`
before applying anything, and uses `reload` rather than `restart` — an invalid
config is rejected while the config already in memory keeps serving the
existing site.

### Before that will work

`techpio.tech` currently resolves to **2.57.91.91**, which is not this box.
Step 1 below has to happen first.

---

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

## Step 4 — publishing it: the Cloudflare Tunnel

**Read this instead of steps 4 and 5 on the box we actually have.** Those two
steps assume nginx on the host with a free share of ports 80 and 443. This box
has neither: `piodesk-edge-1`, the nginx serving **piodesk.com**, owns 80 and
443 on both IPv4 and IPv6, its configuration is generated from a template
outside this repository, and **that application is not to be touched**. A vhost,
a certificate and a reload are all off the table, and no amount of care makes
them otherwise.

cloudflared solves it by turning the direction around. It dials **out** to
Cloudflare and serves the hostname from Cloudflare's edge, so it binds no port,
publishes nothing, needs no inbound firewall rule, and has nothing to contend
with `piodesk-edge-1` over. TLS is terminated at the edge; `deploy/nginx/app.conf`
already tells PHP-FPM the scheme is `https`, so generated URLs are right without
trusting a forwarded header.

### Once, in Cloudflare

1. Create a free account and **Add a site** for `techpio.tech`.
2. Cloudflare gives you two nameservers. Set them at the registrar, replacing
   what is there. **This is the one irreversible-feeling step** — DNS for the
   whole domain moves to Cloudflare. It is reversible by putting the old
   nameservers back, and the A record that points at this box is imported
   automatically, but it does affect every record on the domain, not just this
   one.
3. **Zero Trust → Networks → Tunnels → Create a tunnel**, choose **Cloudflared**,
   name it `foodonthego-review`.
4. Copy the **token** it shows — a long string. That is the credential; treat it
   the way you would a password, and put it straight in `deploy/.env`, not
   through a chat window or a screenshot.
5. On the tunnel's **Public Hostnames** tab, add one:

   | Field | Value |
   | --- | --- |
   | Subdomain | *(leave empty)* |
   | Domain | `techpio.tech` |
   | Service type | `HTTP` |
   | URL | `web:80` |

   `web` is the compose service name. cloudflared runs on the same network and
   resolves it by name — which is why this does not go through `127.0.0.1:8090`.
   That port is bound to the **host's** loopback, and a container's loopback is
   itself; it would never be reachable from cloudflared.

   Add a second hostname for `www.techpio.tech` pointing at the same service if
   you want it to work too.

### On the box

```bash
cd /opt/foodonthego/deploy
printf 'CLOUDFLARE_TUNNEL_TOKEN=%s\n' 'PASTE_THE_TOKEN_HERE' >> .env
docker compose --profile tunnel up -d
docker compose logs --tail 30 tunnel
```

The log should say `Registered tunnel connection` two or four times — one per
Cloudflare edge location. Then `https://techpio.tech` answers.

**The profile matters.** Without `--profile tunnel` the tunnel does not start,
which is deliberate: the stack must run for someone who has no token, and a
compose file that refused to come up without one would make the review
deployment depend on a Cloudflare account.

### The quicker, worse alternative

If the Cloudflare setup is more than you want right now, the stack can be
published on a plain HTTP port instead, with no account, no nameserver change
and no certificate:

```bash
docker compose -f docker-compose.yml -f docker-compose.public-http.yml up -d
```

`http://techpio.tech:8080` then answers, using the A record that already points
at this box.

**It is worse, and the file says so at the top.** There is no TLS: the one-time
code at sign-in and the session token afterwards travel in clear text, readable
by anyone on the network path. For seeded test data with no real customers and
no real payments that is contained, and it is not a configuration to carry into
anything real. The browser will also say "Not secure" on every page, which is a
poor frame for showing somebody a product.

It is a separate file rather than a flag precisely so that publishing to the
internet has to be typed out deliberately every time.

### Stopping it

```bash
docker compose --profile tunnel stop tunnel
```

The site goes dark, everything else keeps running, and nothing on the box
changed. Deleting the tunnel in the dashboard is the permanent version.

---

## Step 4 (alternative) — the vhost, where the host owns nginx

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

## If `.env` stops parsing

```
failed to read /opt/foodonthego/deploy/.env: line 76: unexpected character "+" in variable name
```

Every compose command fails at once, including the ones that would tell you why.
It has already happened once, and the cause was mundane: a private key printed
with `cat` in one command and a `>> .env` append in the next, with the paste
landing in the wrong one. The key's continuation lines are not `NAME=value`, so
the parser stops on the first of them.

**Do not delete and recreate the file.** It holds `APP_KEY` and the MySQL
passwords, and `DB_PASSWORD` is what makes the existing database readable —
regenerating it is how a review deployment loses its data.

```bash
cd /opt/foodonthego/deploy && ./env-repair.sh
```

It keeps comments, blank lines and proper assignments and drops everything else,
which is exactly what stray pasted text is. It checks the required keys survive
**before** replacing the file, so a repair cannot quietly lose `DB_PASSWORD`; if
one would be lost it refuses and leaves your `.env` untouched. Then it shreds its
own backup, because that backup holds whatever was pasted in.

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
