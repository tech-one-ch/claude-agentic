# Check Script

Verifies the Claude Agentic installation — languages, tools, services, Docker, Claude Code, Web IDE.
Run it inside the LXC or VM after installation.

---

## Run from `main` (stable)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh)
```

## Run from `dev` (testing)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/dev/checks/check.sh)
```

## If the repo is cloned locally

```bash
bash checks/check.sh
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
bash checks/check.sh --export

# Export to specific file
bash checks/check.sh --export /tmp/results.txt

# Send to Supabase
bash checks/check.sh --supabase

# Export + Supabase
bash checks/check.sh --export --supabase
```

---

## Supabase integration

Results (summary + per-check details) can be sent to a Supabase table.

### Credentials

The script uses the **anon/publishable key** (not the service_role key).
This key only has INSERT rights on this specific table — safe to use in scripts.

**Option A — prompted at runtime** (key hidden, not shown in terminal):
```bash
bash checks/check.sh --supabase
# → prompts for URL then anon key (input hidden like a password)
```

**Option B — environment variables** (for automation):
```bash
export SUPABASE_URL="https://abc123.supabase.co"
export SUPABASE_KEY="your-anon-key"
bash checks/check.sh --supabase
```

### Where to find your credentials

In your [Supabase dashboard](https://supabase.com/dashboard):

1. Select your project
2. Go to **Project Settings → API**
3. **Project URL** → use as `SUPABASE_URL`
4. **anon / public** key (also called `publishable` in new projects) → use as `SUPABASE_KEY`

> Never use the `service_role` / `secret` key in scripts — it bypasses all security.

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

-- Enable RLS and allow INSERT only for the anon role
ALTER TABLE claude_agentic_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon insert only" ON claude_agentic_checks
  FOR INSERT TO anon WITH CHECK (true);
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
