# Check Script

Verifies the Claude Agentic installation — languages, tools, services, Docker, Claude Code, Web IDE.
Run it inside the LXC or VM after installation.

---

## Run from `main` (stable)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/tests/check.sh)
```

## Run from `dev` (testing)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/dev/tests/check.sh)
```

## If the repo is cloned locally

```bash
bash tests/check.sh
```

---

## Options

| Flag | Description |
|---|---|
| `--export` | Save results to an auto-named file (`check-results-YYYYMMDD-HHMMSS.txt`) |
| `--export <file>` | Save results to a specific file |
| `--supabase` | Send results to Supabase (prompts for credentials) |

Examples:

```bash
# Export to auto-named file
bash tests/check.sh --export

# Export to specific file
bash tests/check.sh --export /tmp/results.txt

# Send to Supabase
bash tests/check.sh --supabase

# Export + Supabase
bash tests/check.sh --export --supabase
```

---

## Supabase integration

Results (summary + per-check details) can be sent to a Supabase table.

### Credentials

Two ways to provide credentials:

**Option A — prompted at runtime** (key hidden, not shown in terminal):
```bash
bash tests/check.sh --supabase
# → prompts for URL then key (input hidden like a password)
```

**Option B — environment variables** (for automation):
```bash
export SUPABASE_URL="https://abc123.supabase.co"
export SUPABASE_KEY="your-service-role-key"
bash tests/check.sh --supabase
```

### Where to find your credentials

In your [Supabase dashboard](https://supabase.com/dashboard):

1. Select your project
2. Go to **Project Settings → API**
3. **Project URL** → use as `SUPABASE_URL`
4. **service_role** secret key → use as `SUPABASE_KEY` (never the anon key for this)

### Create the table (first time only)

The script will automatically show this SQL if the table doesn't exist yet.
Run it once in your [Supabase SQL editor](https://supabase.com/dashboard/project/_/sql/new):

```sql
CREATE TABLE IF NOT EXISTS claude_agentic_checks (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at  timestamptz DEFAULT now(),
  hostname    text,
  env_type    text,
  os_name     text,
  ip          text,
  pass_count  int,
  fail_count  int,
  warn_count  int,
  skip_count  int,
  details     jsonb
);

-- Allow inserts with the service_role key
ALTER TABLE claude_agentic_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role insert" ON claude_agentic_checks
  FOR INSERT WITH CHECK (true);
```

### Data sent

```json
{
  "hostname": "claude-agentic-dev",
  "env_type": "LXC container",
  "os_name": "Ubuntu 24.04 LTS",
  "ip": "192.168.1.218",
  "pass_count": 18,
  "fail_count": 0,
  "warn_count": 0,
  "skip_count": 1,
  "details": [
    { "label": "Node.js",        "status": "pass", "detail": "v22.22.2" },
    { "label": "docker service", "status": "pass", "detail": "active" },
    { "label": "claude",         "status": "pass", "detail": "1.x.x" }
  ]
}
```
