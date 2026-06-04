# Check Script

Verifies the Claude Agentic installation — languages, tools, services, Docker, Claude Code, Web IDE.
Run it inside the LXC or VM after installation.

---

## Run from `main` (stable)

```bash
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash
```

## Run from `dev` (testing)

```bash
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/dev/checks/check.sh | bash
```

---

## Options

| Flag | Description |
|---|---|
| `--export` | Save results to an auto-named file (`check-results-YYYYMMDD-HHMMSS.txt`) |
| `--export <file>` | Save results to a specific file |
| `--supabase` | Send results to Supabase (prompts for missing credentials) |
| `--supabase-url <url>` | Set Supabase project URL directly |
| `--supabase-key <key>` | Set Supabase anon key directly ⚠️ see note below |

### Examples

```bash
# Export to auto-named file
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash -s -- --export

# Export to specific file
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash -s -- --export /tmp/results.txt

# Send to Supabase (interactive prompt)
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash -s -- --supabase

# Send to Supabase with URL pre-filled (key prompted)
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash \
  --supabase-url https://abc123.supabase.co

# Export + Supabase
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash \
  --export --supabase
```

---

## Supabase integration

Results (summary + per-check details) can be sent to a Supabase table.

### Credentials — priority order

The script resolves credentials in this order:
1. **CLI flags** (`--supabase-url`, `--supabase-key`)
2. **Environment variables** (`SUPABASE_URL`, `SUPABASE_KEY`)
3. **Interactive prompt** (URL visible, key hidden like a password)

**Option A — interactive prompt** (recommended, key never visible):
```bash
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash -s -- --supabase
```

**Option B — environment variables** (for automation):
```bash
export SUPABASE_URL="https://abc123.supabase.co"
export SUPABASE_KEY="your-publishable-or-anon-key"
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash -s -- --supabase
```

**Option C — CLI flags** (URL only recommended, key via flag is visible in bash history):
```bash
# URL only — key will be prompted (hidden)
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash \
  --supabase-url https://abc123.supabase.co

# URL + key — convenient but key appears in bash history ⚠️
curl -fsSL https://raw.githubusercontent.com/tech-one-ch/claude-agentic/main/checks/check.sh | bash \
  --supabase-url https://abc123.supabase.co \
  --supabase-key your-anon-key
```

### Where to find your credentials

In your [Supabase dashboard](https://supabase.com/dashboard):

1. Select your project
2. Go to **Project Settings → API**
3. **Project URL** → use as `SUPABASE_URL`
4. For the key → use as `SUPABASE_KEY`:

| Your project | Section in dashboard | Key to use |
|---|---|---|
| Recent (new UI) | **Publishable and secret API keys** | `publishable` key |
| Older project | **Legacy anon, service_role API keys** | `anon` key |

Both map to the same PostgreSQL `anon` role — the RLS policy below works with either.

> Never use the `secret` / `service_role` key in scripts — it bypasses all security.

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
