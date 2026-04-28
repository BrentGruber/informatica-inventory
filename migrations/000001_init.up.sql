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

CREATE INDEX idx_resources_environment_type ON resources(environment_id, resource_type_id);
CREATE INDEX idx_resources_name ON resources(name);
CREATE INDEX idx_resources_external_key ON resources(external_key);
CREATE INDEX idx_resources_detail_json ON resources USING GIN(detail_json);
CREATE INDEX idx_resource_relationships_from ON resource_relationships(from_resource_id);
CREATE INDEX idx_resource_relationships_to ON resource_relationships(to_resource_id);
CREATE INDEX idx_sync_runs_status ON sync_runs(status);
CREATE INDEX idx_sync_tasks_status ON sync_tasks(status);
