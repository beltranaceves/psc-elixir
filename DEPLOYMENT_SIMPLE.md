# PSC Deployment Guide

Deploy your Phoenix app to CapRover using the CLI in 3 steps.

## 1. Setup (One-time)

```bash
# Install CapRover CLI
npm install -g caprover

# Login to your CapRover instance
caprover login
# Enter CapRover URL, username, password, and a machine name
```

## 2. Deploy

```bash
# From project root
caprover deploy
```

Select your CapRover machine when prompted. The CLI automatically:
- Builds Docker image using `captain-definition`
- Pushes to CapRover
- Deploys your app

## 3. Configure

**In CapRover Dashboard**, set environment variables for your app:

```
DATABASE_URL=ecto://postgres:e6c1640e8813c54b@srv-captain--psc-postgres:5432/postgres
PHX_HOST=yourdomain.com
SECRET_KEY_BASE=[run: mix phx.gen.secret]
MIX_ENV=prod
PORT=4000
POOL_SIZE=8
```

Click **Save & Update**.

## 4. Run Migrations

```bash
docker exec captain-psc /app/bin/psc eval "Psc.Release.migrate"
```

Expected output: `Migrations completed successfully`

## 5. Add Domain

**In CapRover Dashboard** → HTTP Settings:
- Add domain: `yourdomain.com`
- Enable HTTPS (auto-provisioned)
- Click **Update**

**Done!** Your app is live at `https://yourdomain.com`

---

## Redeployment (Code Updates)

```bash
git add .
git commit -m "Your changes"
caprover deploy
```

## Multiple Instances (Recommended for 4-core VPS)

**In CapRover Dashboard** → Instance Count: `2`

NGINX automatically load-balances. This enables:
- Higher availability
- Zero-downtime deployments
- Better CPU distribution

With 2 instances, use `POOL_SIZE=8` (4 connections per instance = 16 total).

## PostgreSQL

Already running in CapRover as `psc-postgres`:
- Host: `srv-captain--psc-postgres:5432`
- User: `postgres`
- Password: `e6c1640e8813c54b`
- Database: `postgres`

## Local Testing

Before deploying, test locally:

```bash
docker compose up
# Visit http://localhost:4000
docker exec psc-app /app/bin/psc eval "Psc.Release.migrate"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `caprover` not found | `npm install -g caprover` |
| Deployment fails | Verify `captain-definition` exists in project root |
| App won't start | Check CapRover logs, verify all env vars are set |
| Connection to DB fails | Verify `DATABASE_URL` and PostgreSQL is running |
| Domain shows 404 | Wait 2 min for NGINX reload, check DNS |
| High memory | Reduce `POOL_SIZE` or reduce instance count |

## Resources

- `captain-definition` - Deployment config (references Dockerfile)
- `Dockerfile` - Docker build instructions
- `lib/psc/release.ex` - Migration helper
- `docker-compose.yml` - Local testing

## Your VPS: 4 cores, 24GB RAM, 1TB storage

**Recommended setup:**
- 2 app instances (for HA + zero-downtime deploys)
- PostgreSQL (already running)
- NGINX/SSL (CapRover handles it)
- Headroom for OS, caching, buffers

This leaves plenty of resources for growth.

---

**First time?** Run `mix phx.gen.secret` to generate your `SECRET_KEY_BASE`, then follow steps 1-5 above.
