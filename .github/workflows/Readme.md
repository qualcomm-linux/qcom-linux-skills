# List of workflows and actions
This folder contains workflows that are helpful for maintaining a smooth and secure development process. The workflows should be enabled for open-source projects.

Workflows:
1. `qcom-preflight-checks.yml` - This workflow runs several preflight checks, including copyight, email, repolinter, and security checks.  See [qualcomm/qcom-actions](https://github.com/qualcomm/qcom-actions)
2. `stale-issues.yaml` - This workflow will periodically run every 30 days to check for stalled issues and PRs. If the workflow detects any stalled issues and/or PRs, it will automatically leave just a comment to draw attention.
3. `catalog-checks.yml` - This workflow enforces the skill catalog conventions: it runs `ci/check-catalog.py` (frontmatter, naming, script headers, README/ROADMAP/marketplace cross-references), validates every skill with the Agent Skills reference validator (`skills-ref`), runs shellcheck and a Python compile check over the helper scripts, exercises the `install.sh` self-test, and validates `.claude-plugin/marketplace.json` with `claude plugin validate`.
