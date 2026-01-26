# HAR Agents - Human-Assisted Repository Discovery

HAR (Human-Assisted Repository) agents discover packages from obscure, legacy, or unmaintained sources.

## Agents

### 1. GitHub Search (`github-search.sh`)

Searches GitHub API for package repositories by name and language.

**Features:**
- Searches GitHub repositories by package name and programming language
- Returns results with confidence scoring based on star count
- Supports callback URLs for async notification
- Writes results to `/tmp/opsm-har-ingest/results/`

**Dependencies:**
- `bash`
- `curl`
- `jq`

**Usage:**
```bash
./github-search.sh  # Runs in watch mode, polls queue every 5s
```

**Task Format:**
```json
{
  "imp": {
    "package": "idris2-json",
    "forth": "idris2"
  },
  "callbackUrl": "http://localhost:8080/har/callback"
}
```

**Result Format:**
```json
{
  "taskId": "abc123",
  "agent": "github-search",
  "package": "idris2-json",
  "found": true,
  "repository": "https://github.com/idris-community/idris2-json",
  "description": "JSON library for Idris2",
  "confidence": "high",
  "metadata": {
    "stars": 42
  }
}
```

---

### 2. Web Scraper (`web-scraper.jl`)

Searches for packages using web search engines and pattern matching.

**Features:**
- Tries last known URL first (if provided)
- Checks known repository patterns (github.com/lang/package, etc.)
- Falls back to DuckDuckGo HTML search
- Filters results for code hosting sites

**Dependencies:**
- `julia`
- Julia packages: `HTTP`, `JSON3`

**Installation:**
```bash
julia -e 'using Pkg; Pkg.add(["HTTP", "JSON3"])'
```

**Usage:**
```bash
./web-scraper.jl  # Runs in watch mode
```

**Task Format:**
```json
{
  "imp": {
    "package": "idris2-network",
    "forth": "idris2",
    "last_known_url": "https://github.com/idris-community/network"
  }
}
```

**Result Format:**
```json
{
  "taskId": "abc123",
  "agent": "web-scraper",
  "package": "idris2-network",
  "found": true,
  "repository": "https://github.com/idris-community/network",
  "confidence": "high",
  "metadata": {
    "source": "last_known_url",
    "language": "idris2"
  }
}
```

---

### 3. Mirror Finder (`mirror-finder.sh`)

Searches package archives and mirror services for historical versions.

**Features:**
- Checks Software Heritage Archive
- Checks Internet Archive Wayback Machine
- Checks Debian snapshot service
- Checks Fedora archives (koji)

**Dependencies:**
- `bash`
- `curl`
- `jq`

**Usage:**
```bash
./mirror-finder.sh  # Runs in watch mode
```

**Task Format:**
```json
{
  "imp": {
    "package": "legacy-lib",
    "repository": "https://bitbucket.org/old-repo/legacy-lib"
  }
}
```

**Result Format:**
```json
{
  "taskId": "abc123",
  "agent": "mirror-finder",
  "package": "legacy-lib",
  "found": true,
  "mirrors": [
    "https://archive.softwareheritage.org/...",
    "https://web.archive.org/web/..."
  ],
  "confidence": "high",
  "metadata": {
    "mirrorCount": 2
  }
}
```

---

## Running Agents

### Developsment
```bash
# Run all agents in separate terminals:
./github-search.sh
./web-scraper.jl
./mirror-finder.sh
```

### Production (systemd)

**Quick Install:**
```bash
# Automated installation (recommended):
sudo ./install-services.sh
```

**Manual Installation:**
```bash
# Create system user:
sudo useradd --system --no-create-home --shell /bin/false opsm

# Create queue directory:
sudo mkdir -p /tmp/opsm-har-ingest/{results,processed}
sudo chown -R opsm:opsm /tmp/opsm-har-ingest

# Install systemd services:
sudo cp *.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable har-github-search har-web-scraper har-mirror-finder
sudo systemctl start har-github-search har-web-scraper har-mirror-finder

# Check status:
sudo systemctl status har-*
```

---

## Queue Directory Structure

```
/tmp/opsm-har-ingest/
├── *.imp.json          # Pending tasks
├── results/            # Completed task results
│   └── *.result.json
└── processed/          # Archived tasks
    └── *.imp.json
```

---

## Integration with OPSM

The Agentic registry adapter (`lib/opsm/registries/agentic.ex`) submits tasks to the HAR queue:

```elixir
# OPSM submits task
Opsm.Registries.Agentic.fetch_package("idris2-json", "latest")

# Task written to /tmp/opsm-har-ingest/task-abc123.imp.json

# HAR agent processes task
# Result written to /tmp/opsm-har-ingest/results/task-abc123.result.json

# OPSM polls for result
Opsm.HarQueue.await_result(task_id, timeout: 30_000)
```

---

## Confidence Scoring

| Confidence | Meaning |
|-----------|---------|
| `high` | Direct match with high indicators (stars, known source) |
| `medium` | Pattern match or archive found |
| `low` | Web search result, unverified |

---

## API Rate Limits

- **GitHub API**: 60 req/hour unauthenticated, 5000 req/hour authenticated
- **DuckDuckGo**: No official limit, be respectful
- **Software Heritage**: No official limit
- **Wayback Machine**: No official limit

To avoid rate limits:
1. Add GitHub token to `~/.netrc` or environment variable
2. Implement caching for recent results
3. Use exponential backoff on errors

---

## Security Considerations

- HAR agents run external commands (`curl`, web requests)
- Task JSON is parsed and could contain malicious data
- Agents should run in sandboxed environment
- Consider using AppArmor/SELinux profiles
- Validate all URLs before making requests
- Use OPSM's `Verified.Url` module for URL validation

---

## Troubleshooting

**Agent not processing tasks:**
```bash
# Check queue directory exists
ls -la /tmp/opsm-har-ingest/

# Check agent logs
journalctl -u har-github-search -f

# Test task manually
echo '{"imp":{"package":"test","forth":"idris2"}}' > /tmp/opsm-har-ingest/test.imp.json
```

**No results returned:**
```bash
# Check results directory
ls -la /tmp/opsm-har-ingest/results/

# Check processed directory
ls -la /tmp/opsm-har-ingest/processed/
```

**Rate limit errors:**
```bash
# Add GitHub token to environment
export GITHUB_TOKEN=ghp_yourtoken

# Or add to ~/.netrc:
echo "machine api.github.com login YOUR_USERNAME password YOUR_TOKEN" >> ~/.netrc
```

---

## Future Enhancements (v2.0)

- [ ] ML-based package discovery
- [ ] Distributed agent coordination
- [ ] Result caching layer
- [ ] GitHub authentication support
- [ ] Parallel task processing
- [ ] Priority queue for urgent requests
- [ ] Agent health monitoring dashboard
