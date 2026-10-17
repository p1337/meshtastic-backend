# Werkbeleg: Supabase cloud foundation

**Status:** preparatory database migration and PostgreSQL isolation tests. No Supabase project created, no hosted data service active, no paid plan purchased. Native app 1.1 is published and still talks to the earlier single-business pilot API. This SQL is not a compatible replacement URL for that API.

## Included

- Separate organizations, memberships, customers, projects, reports, append-only messages, invitations and media reservations.
- Row-level security on every business table; membership derived from authenticated Supabase `auth.uid()`.
- Composite organization/project/customer references block cross-business associations.
- Five-seat default and allowed 5/10/20 tier sizes; clients cannot change seats, memberships or storage counters directly.
- Owner/admin invitations reserve seats, expire after 48 hours, are stored hashed and can be redeemed once by an authenticated account.
- Chat author and creation time protected from client spoofing; cursor index for incremental reads. Actual real-time client still needs implementation.
- Private media bucket; authorized members can read finalized objects. Direct authenticated uploads deliberately have no write policy yet.
- A quota reservation RPC serializes allocation on the organization row. New test organizations receive **100 MB**, not the proposed commercial 5/10/20 GB. Provider Free quota is shared across the whole project, not awarded to each business.

## Not included / activation gates

Do not call this a deployed cloud or completed hosted product. Native Supabase sign-in/session refresh, data migration, record-level offline sync, trusted media uploader/finalizer, reservation expiry/reclamation, deletion workflows, billing verification, ownership transfer and operational backups are still required. The uploader must validate actual file bytes before using any server secret to write media; trusting only a declared byte count is insufficient. Never open Storage INSERT to clients merely to make the test pass.

The scheme intentionally blocks uploads until that trusted path exists. No service-role key belongs in the iOS app or public source. Supabase Auth supplies user identity; the local CI identity shim does not test hosted JWT verification or real Storage API behavior.

## Free test setup after account connection

1. Create a new development project on Free in fixed Frankfurt eu-central-1 region; do not modify an unrelated existing project. No automatic paid upgrade.
2. Review this migration and run it against the new project. Keep public signup disabled initially and create two operator-controlled synthetic test accounts.
3. Use account A to create one test business via `wb_create_business`; invite account B and test owner/editor/viewer access with real Supabase Auth tokens.
4. Verify RLS and private bucket behavior against the hosted service before connecting customer data. The migration uses a conservative 100 MB reservation cap per test business; Free currently includes 1 GB file storage for the project as a whole.
5. Implement and test the trusted uploader, then add native Supabase login and record/media sync in a separate app revision. Existing 1.1 backup import must migrate rather than silently replace customer data.

Client configuration may contain project URL and publishable key. Service credentials stay server-side. Do not ask the user to paste passwords or secret keys into chat; prefer the Supabase connection.

## Reproducible checks

Workflow `.github/workflows/werkbeleg-cloud-ci.yml` starts disposable PostgreSQL 16 and executes:

```sh
psql -X -v ON_ERROR_STOP=1 -q -f werkbeleg-cloud/tests/bootstrap.sql
psql -X -v ON_ERROR_STOP=1 -q -f werkbeleg-cloud/supabase/migrations/202610170001_tenant_foundation.sql
psql -X -v ON_ERROR_STOP=1 -qAt -f werkbeleg-cloud/tests/tenant_isolation.sql
```

`bootstrap.sql` is **CI-only**: it simulates the names of Supabase auth/storage tables and authenticated identities. Never run it on hosted Supabase. Tests exercise PostgreSQL RLS/privileges, references, plan escalation denial, single-use invitations, quota rejection and private media reads. They are not a substitute for hosted Supabase integration tests or a production security review.

Primary references:

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/storage/schema/design
- https://supabase.com/pricing

Pricing/product assumptions: see [WERKBELEG_CLOUD_PLAN.md](../WERKBELEG_CLOUD_PLAN.md). Paid memberships remain proposals until StoreKit configuration and verification exist; do not grant a paid tier merely from a client-selected label.


## EU residency gate

User requires European business-data storage. Prefer Frankfurt eu-central-1. Supabase core database, Auth, Storage and backups can be regional, but global CDN, support and operational processing have exceptions. Do not equate choosing Frankfurt with an EU-only guarantee. Before customer upload validate all data paths or choose an EU-hosted alternative. No customer data or hosted project exists yet. Native 1.1.1 disables network speech fallback. Provider reference: https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq .
