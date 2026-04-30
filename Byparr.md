Migration checklist: FlareSolverr → ByParr
Backup
Save existing FlareSolverr config and any custom scripts.
Note current service URL, port, API key, and integrations (Prowlarr/Jackett/etc.).
Prepare environment
Ensure Docker (recommended) or Python/venv + dependencies available.
Allocate sufficient CPU/RAM and persistent storage for browser cache.
Install ByParr
Preferred: pull official/community Docker image for your architecture and run.
Or: clone repo, create venv, install requirements, and run per README.
Configure ByParr
Set port and host to mirror previous FlareSolverr (default FlareSolverr: 8191) to simplify integrations.
Add API key matching previous FlareSolverr key (or update clients later).
Configure browser options (headless, user-agent, proxies) similar to FlareSolverr settings.
Start service & test health
Start container/service and check logs for errors.
Verify HTTP health endpoint (e.g., /health or root) responds.
Update integrations
Point each client (Prowlarr, Jackett, other tools) to ByParr URL:port.
If you kept the same API key and port, only restart clients may be needed.
Functional tests
Run sample requests from each integration (search or test button).
Compare results to FlareSolverr behavior; check for errors, timeouts, CAPTCHAs.
Test multiple concurrent requests to observe stability.
Tuning
Adjust browser concurrency, timeouts, and headless flags for reliability.
Configure proxy or CAPTCHA solver integrations if required.
Monitor resource use
Monitor CPU, RAM, and process count under normal load for first 24–72 hours.
Increase resources or limit concurrency if instability appears.
Rollback plan
Keep FlareSolverr service available (on different port) until confident.
Re-point integrations back to FlareSolverr if major issues occur.
Finalize
Remove FlareSolverr once satisfied.
Document new service endpoint, credentials, and any config changes.

Below are concrete steps and example commands to migrate with Prowlarr primary and Jackett as backup.

Assumptions (reasonable defaults)

You run services on Linux with Docker.
FlareSolverr was on http://localhost:8191 with API key FS_KEY.
You want ByParr on the same host and port, using same API key to minimize changes.
Replace FS_KEY with your real key.
Pull and run ByParr (Docker)
Stop existing FlareSolverr container: docker stop flaresolverr || true docker rm flaresolverr || true
Pull/run ByParr (example):
docker run -d \
--name byparr \
--restart unless-stopped \
-p 8191:8191 \
-e BYPARR_API_KEY=FS_KEY \
-v /path/to/byparr/config:/app/config \
ghcr.io/byparr/byparr:latest
Notes:

Adjust image name/tag if using a different repository.
Use same port 8191 so Prowlarr/Jackett need no URL changes.
Map a config volume for persistence.
If you prefer non-Docker (Python)
Clone, create venv, install, set env var, run: git clone https://github.com/byparr/byparr.git cd byparr python -m venv .venv source .venv/bin/activate pip install -r requirements.txt export BYPARR_API_KEY=FS_KEY python app.py
Configure ByParr to match FlareSolverr behavior
API key: BYPARR_API_KEY=FS_KEY (or update Prowlarr later).
Browser args / headless: set via ByParr config file or envs per repo README.
Proxy (if used): pass same proxy envs to container (HTTP_PROXY/HTTPS_PROXY) or configure in ByParr.
Verify service health
Check logs: docker logs -f byparr
Test endpoint: curl -s -X POST "http://localhost:8191/v1" -H "Content-Type: application/json" -d '{"cmd":"healthcheck","apiKey":"FS_KEY"}'
Expect a JSON success response.

Point Prowlarr → ByParr (if not using same URL/key)
In Prowlarr: Settings → Indexers → Downloader (or Proxy?) → FlareSolverr settings:
URL: http://localhost:8191
API Key: FS_KEY
Save and use Prowlarr’s test button to confirm.
Point Jackett → ByParr (backup)
In Jackett: Settings → Connections / FlareSolverr:
URL: http://localhost:8191
API Key: FS_KEY
Test a single indexer; keep Jackett configured as fallback.
Functional tests
In Prowlarr: run a few indexer searches and import flows; confirm results and no captcha errors.
In Jackett: test a couple of indexers to ensure it can also use ByParr when needed.
Load / concurrency test
Run simultaneous searches from Prowlarr + Jackett and watch ByParr logs and host resource usage: top, htop, docker stats byparr
Tune timeouts and concurrency
If you see timeouts, increase ByParr request timeout or Prowlarr’s FlareSolverr timeout.
If high memory/CPU, limit concurrency or increase host resources.
Rollback plan
If issues, stop byparr and restart FlareSolverr: docker stop byparr && docker rm byparr docker run -d --name flaresolverr -p 8191:8191 -e FLORESOLVERR_API_KEY=FS_KEY
Finalize
When stable, document service, disable old container, and optionally enable restart policies and monitoring.
