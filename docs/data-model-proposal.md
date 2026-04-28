# Data Model Proposal

## Goal

This document proposes application-level data models and a database schema for caching Informatica Cloud metadata locally.

The design assumes the Informatica REST APIs expose metadata in several layers:
- organization / environment discovery
- principals or service accounts
- high-level resource listings by type
- detailed resource payloads per object
- relationships between resources, such as jobs, sources, targets, and folders

Because resource shapes vary significantly across Informatica object types, the model should support both:
- normalized queryable metadata
- raw JSON payload retention

That lets the system remain useful early without needing to perfectly model every resource type up front.

## Research-informed design assumptions

Based on common Informatica Cloud / IICS REST API patterns, the system should expect to work with concepts like:
- environments or org-scoped runtimes
- users, service accounts, and roles
- projects / folders / locations
- tasks and taskflows
- mappings or mapping tasks
- connections
- schedules
- runtime or agent-related metadata
- source and target objects
- execution metadata later, if desired

The system should also expect these API characteristics:
- list endpoints and detail endpoints may return different field sets
- not all resource types will expose strong foreign keys consistently
- nested JSON structures may contain useful graph relationships that should be preserved raw even before they are normalized

## Modeling strategy

Use a layered model.

### Layer 1: sync and control metadata
Tracks what was synced, when, by which workflow, and with what result.

### Layer 2: environment and principal metadata
Tracks environments and the service accounts used to enumerate them.

### Layer 3: generic resources
A unified resource table supports broad querying across heterogeneous resource types.

### Layer 4: typed detail and raw payload storage
Use JSONB for full payloads and optionally typed extension tables for high-value resource types.

### Layer 5: relationships / graph edges
Capture source-target and dependency-style relationships so the frontend can build graph views.

## Proposed application models

## Environment
Represents an Informatica environment or logical tenant context.

Suggested fields:
- `id`
- `external_id`
- `name`
- `description`
- `region`
- `organization_id`
- `organization_name`
- `status`
- `base_url`
- `metadata_json`
- `first_seen_at`
- `last_seen_at`
- `last_synced_at`

Notes:
- `external_id` should be the stable Informatica identifier if one exists
- `metadata_json` stores non-normalized environment fields

## ServiceAccount
Represents a principal that may be used to access an environment.

Suggested fields:
- `id`
- `environment_id`
- `external_id`
- `name`
- `username`
- `principal_type`
- `is_admin`
- `is_active`
- `credential_ref`
- `metadata_json`
- `first_seen_at`
- `last_seen_at`

Notes:
- `credential_ref` should point to a secure secret resolver, not raw secrets
- `is_admin` is important because the sync workflow depends on it

## ResourceType
Represents the categories of Informatica resources the system knows how to cache.

Suggested fields:
- `id`
- `code`
- `name`
- `api_collection_path`
- `api_detail_path_template`
- `is_enabled`
- `supports_detail_fetch`
- `notes`

Examples:
- `task`
- `mapping`
- `mapping_task`
- `taskflow`
- `connection`
- `schedule`
- `folder`

## Resource
Represents a generic Informatica object cached by the system.

Suggested fields:
- `id`
- `environment_id`
- `resource_type_id`
- `external_id`
- `external_key`
- `name`
- `display_name`
- `path`
- `folder_path`
- `status`
- `subtype`
- `description`
- `version`
- `created_by`
- `updated_by`
- `created_at_source`
- `updated_at_source`
- `first_seen_at`
- `last_seen_at`
- `last_synced_at`
- `is_deleted`
- `summary_json`
- `detail_json`

Notes:
- `external_key` can be a fallback stable key when the API has awkward identifiers
- `summary_json` stores list response payload
- `detail_json` stores detail response payload
- this is the core table the GraphQL layer will likely query most often

## ResourceRelationship
Represents graph edges between Informatica resources.

Suggested fields:
- `id`
- `environment_id`
- `from_resource_id`
- `to_resource_id`
- `relationship_type`
- `directionality`
- `metadata_json`
- `first_seen_at`
- `last_seen_at`

Examples of relationship types:
- `uses_connection`
- `reads_from`
- `writes_to`
- `depends_on`
- `belongs_to_folder`
- `scheduled_by`
- `invokes_task`

Notes:
- this table is key for future graph visualization
- relationships may be extracted during detail normalization

## SyncRun
Represents a workflow execution.

Suggested fields:
- `id`
- `run_type`
- `status`
- `environment_id` nullable
- `resource_type_id` nullable
- `triggered_by`
- `workflow_id`
- `workflow_run_id`
- `started_at`
- `finished_at`
- `stats_json`
- `error_summary`

Examples of `run_type`:
- `full_sync`
- `environment_sync`
- `resource_type_sync`
- `resource_detail_sync`

## SyncTask
Represents a finer-grained unit of work within a sync run.

Suggested fields:
- `id`
- `sync_run_id`
- `environment_id`
- `resource_type_id`
- `resource_id` nullable
- `task_key`
- `status`
- `attempt`
- `started_at`
- `finished_at`
- `stats_json`
- `error_message`

This is useful for visibility and retries.

## SyncError
Represents captured sync failures in a structured way.

Suggested fields:
- `id`
- `sync_run_id`
- `sync_task_id` nullable
- `environment_id` nullable
- `resource_type_id` nullable
- `resource_id` nullable
- `error_class`
- `error_code`
- `message`
- `details_json`
- `created_at`

## Optional typed extension tables

These are not required on day one, but likely worthwhile once specific resource types become important.

### ConnectionDetail
Useful for connection inventory and graph expansion.

Suggested fields:
- `resource_id`
- `connection_type`
- `connector_name`
- `runtime_environment`
- `host`
- `database_name`
- `schema_name`
- `authentication_type`
- `is_runtime_valid`
- `attributes_json`

### TaskDetail
Useful for jobs and operational inventory.

Suggested fields:
- `resource_id`
- `task_type`
- `schedule_name`
- `is_enabled`
- `source_count`
- `target_count`
- `folder_name`
- `attributes_json`

### MappingDetail
Useful for lineage-like extraction.

Suggested fields:
- `resource_id`
- `mapping_type`
- `source_count`
- `target_count`
- `transformation_count`
- `attributes_json`

## Proposed relational schema

## environments
```sql
CREATE TABLE environments (
  id BIGSERIAL PRIMARY KEY,
  external_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  region TEXT,
  organization_id TEXT,
  organization_name TEXT,
  status TEXT,
  base_url TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_synced_at TIMESTAMPTZ,
  UNIQUE (external_id)
);
```

## service_accounts
```sql
CREATE TABLE service_accounts (
  id BIGSERIAL PRIMARY KEY,
  environment_id BIGINT NOT NULL REFERENCES environments(id) ON DELETE CASCADE,
  external_id TEXT,
  name TEXT NOT NULL,
  username TEXT,
  principal_type TEXT,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  credential_ref TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (environment_id, name)
);
```

## resource_types
```sql
CREATE TABLE resource_types (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  api_collection_path TEXT,
  api_detail_path_template TEXT,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  supports_detail_fetch BOOLEAN NOT NULL DEFAULT true,
  notes TEXT
);
```

## resources
```sql
CREATE TABLE resources (
  id BIGSERIAL PRIMARY KEY,
  environment_id BIGINT NOT NULL REFERENCES environments(id) ON DELETE CASCADE,
  resource_type_id BIGINT NOT NULL REFERENCES resource_types(id) ON DELETE RESTRICT,
  external_id TEXT NOT NULL,
  external_key TEXT,
  name TEXT NOT NULL,
  display_name TEXT,
  path TEXT,
  folder_path TEXT,
  status TEXT,
  subtype TEXT,
  description TEXT,
  version TEXT,
  created_by TEXT,
  updated_by TEXT,
  created_at_source TIMESTAMPTZ,
  updated_at_source TIMESTAMPTZ,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_synced_at TIMESTAMPTZ,
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  detail_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (environment_id, resource_type_id, external_id)
);
```

## resource_relationships
```sql
CREATE TABLE resource_relationships (
  id BIGSERIAL PRIMARY KEY,
  environment_id BIGINT NOT NULL REFERENCES environments(id) ON DELETE CASCADE,
  from_resource_id BIGINT NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  to_resource_id BIGINT NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  relationship_type TEXT NOT NULL,
  directionality TEXT NOT NULL DEFAULT 'directed',
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (from_resource_id, to_resource_id, relationship_type)
);
```

## sync_runs
```sql
CREATE TABLE sync_runs (
  id BIGSERIAL PRIMARY KEY,
  run_type TEXT NOT NULL,
  status TEXT NOT NULL,
  environment_id BIGINT REFERENCES environments(id) ON DELETE SET NULL,
  resource_type_id BIGINT REFERENCES resource_types(id) ON DELETE SET NULL,
  triggered_by TEXT,
  workflow_id TEXT,
  workflow_run_id TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  stats_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_summary TEXT
);
```

## sync_tasks
```sql
CREATE TABLE sync_tasks (
  id BIGSERIAL PRIMARY KEY,
  sync_run_id BIGINT NOT NULL REFERENCES sync_runs(id) ON DELETE CASCADE,
  environment_id BIGINT REFERENCES environments(id) ON DELETE SET NULL,
  resource_type_id BIGINT REFERENCES resource_types(id) ON DELETE SET NULL,
  resource_id BIGINT REFERENCES resources(id) ON DELETE SET NULL,
  task_key TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  stats_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_message TEXT
);
```

## sync_errors
```sql
CREATE TABLE sync_errors (
  id BIGSERIAL PRIMARY KEY,
  sync_run_id BIGINT REFERENCES sync_runs(id) ON DELETE CASCADE,
  sync_task_id BIGINT REFERENCES sync_tasks(id) ON DELETE CASCADE,
  environment_id BIGINT REFERENCES environments(id) ON DELETE SET NULL,
  resource_type_id BIGINT REFERENCES resource_types(id) ON DELETE SET NULL,
  resource_id BIGINT REFERENCES resources(id) ON DELETE SET NULL,
  error_class TEXT,
  error_code TEXT,
  message TEXT NOT NULL,
  details_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## Recommended indexes

```sql
CREATE INDEX idx_resources_environment_type ON resources(environment_id, resource_type_id);
CREATE INDEX idx_resources_name ON resources(name);
CREATE INDEX idx_resources_external_key ON resources(external_key);
CREATE INDEX idx_resources_detail_json ON resources USING GIN(detail_json);
CREATE INDEX idx_resource_relationships_from ON resource_relationships(from_resource_id);
CREATE INDEX idx_resource_relationships_to ON resource_relationships(to_resource_id);
CREATE INDEX idx_sync_runs_status ON sync_runs(status);
CREATE INDEX idx_sync_tasks_status ON sync_tasks(status);
```

## Why this schema is a good fit

### 1. It tolerates messy APIs
The raw JSON columns let the system preserve source truth even when normalization is incomplete.

### 2. It supports a graph UI later
The `resource_relationships` table is enough to power node/edge rendering without jumping to a graph database immediately.

### 3. It supports operational visibility
`sync_runs`, `sync_tasks`, and `sync_errors` make the system observable and retry-friendly.

### 4. It supports gradual typing
You can begin with generic resources and later add extension tables for important resource types.

## First practical implementation slice

The most reasonable first slice is:
- environments
- service accounts
- resource_types
- resources
- sync_runs
- sync_tasks

And then add:
- resource_relationships
- sync_errors
- typed extension tables

once the first end-to-end resource sync is working.

## Suggested first resource types to support

A good initial shortlist:
- connections
- tasks
- mappings or mapping tasks
- taskflows
- schedules
- folders/projects

These will give the most immediate value for inventory and future graphing.

## Final recommendation

Start with a **generic resource model plus JSONB payload storage**, not an overly specialized schema.

That gives you:
- speed of initial implementation
- safety against API inconsistency
- room to support GraphQL and graph rendering later
- a path to gradually normalize the most valuable object types over time
