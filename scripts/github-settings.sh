#!/usr/bin/env bash
#
# The repository's settings on GitHub, applied through its API, so they can be read,
# reviewed and applied again. Every call sets a value: running it twice changes nothing.
#
#   scripts/github-settings.sh [owner/repo]     # needs `gh auth login` as an admin
set -euo pipefail

repo=${1:-Turi-Industries/homelabus-catalog}
api() { gh api --silent -H "Accept: application/vnd.github+json" "$@"; }
step() { printf '• %s\n' "$*"; }

step "description, features, merging"
api -X PATCH "repos/$repo" --input - <<'JSON'
{
  "description": "The applications Homelabus installs: a folder per app, reaching every house through a signed index, with no release.",
  "homepage": "https://turi-industries.github.io/homelabus-catalog/index.json",
  "has_wiki": false,
  "has_projects": false,
  "has_issues": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_update_branch": true,
  "delete_branch_on_merge": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY"
}
JSON

step "topics"
api -X PUT "repos/$repo/topics" --input - <<'JSON'
{ "names": ["homelab", "self-hosted", "docker-swarm", "catalog"] }
JSON

# A pull request from anyone runs the workflows: the token reads, and only the actions
# named here run, each by its commit.
step "Actions: read-only token, named actions only, pinned by commit"
api -X PUT "repos/$repo/actions/permissions" --input - <<'JSON'
{ "enabled": true, "allowed_actions": "selected", "sha_pinning_required": true }
JSON
api -X PUT "repos/$repo/actions/permissions/selected-actions" --input - <<'JSON'
{ "github_owned_allowed": true, "verified_allowed": false, "patterns_allowed": ["fsfe/reuse-action@*"] }
JSON
api -X PUT "repos/$repo/actions/permissions/workflow" --input - <<'JSON'
{ "default_workflow_permissions": "read", "can_approve_pull_request_reviews": false }
JSON

step "Dependabot alerts (Renovate opens the pull requests)"
api -X PUT "repos/$repo/vulnerability-alerts"
api -X DELETE "repos/$repo/automated-security-fixes"

step "secret scanning and push protection"
api -X PATCH "repos/$repo" --input - <<'JSON'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
api -X PUT "repos/$repo/private-vulnerability-reporting"

# `main` moves by a pull request validation passed, and is never rewritten: the index
# carries every version ever merged, and a rewritten history would hide one. The owner
# alone may bypass it — one maintainer cannot require a second reviewer.
step "the rules on main"
ruleset=$(cat <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "hlb catalog validate" },
          { "context": "Licences" } ] } }
  ]
}
JSON
)
id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')
if [[ -n $id ]]; then
    api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$ruleset"
else
    api -X POST "repos/$repo/rulesets" --input - <<<"$ruleset"
fi

# A mirrored hlb verified today is the one verified tomorrow.
step "immutable releases"
api -X PUT "repos/$repo/immutable-releases"

step "done"
