# Informatica Inventory

A service for caching Informatica Cloud metadata locally.

## Goal

Build an application that uses Informatica Cloud REST APIs to discover all environments, enumerate resources, pull detailed metadata for those resources, and cache the results in a local database.

The system should support:
- a REST API frontend
- a distributed worker backend
- parallelized metadata collection
- durable local caching
- repeatable sync workflows
- visibility into sync state and failures

## Primary workflow

The core metadata sync workflow should look like this:

1. query Informatica to discover all environments
2. for each environment, find a service account with admin role
3. for each resource type to cache, trigger a task for that environment
4. for each task:
   - resolve admin credentials
   - list all resources of that type in the environment
5. for each resource returned:
   - fetch full resource details
   - upsert the normalized record into the database
6. record sync results, errors, and timestamps

This architecture is a good fit for fan-out/fan-in execution with retries and resumability.

## Recommended starting stack

### Application layer
- **Go**
- **Gin** for the REST API

Why:
- strong concurrency model
- easy static binaries
- good fit for control-plane style services
- straightforward deployment and operations

### Workflow and distributed workers
- **Temporal**

Why:
- ideal for multi-step metadata sync workflows
- supports fan-out execution cleanly
- built-in retries, backoff, and resumability
- good visibility into workflow state
- avoids needing a separate queue/broker in v1

### Database
- **Postgres**

Why:
- strong fit for durable metadata storage
- easy upserts
- relational structure maps well to environments, resources, sync runs, and errors

### Database access
- **sqlc + pgx**

Why:
- typed query generation
- explicit SQL control
- avoids heavy ORM complexity early

### Logging and migrations
- **Zap** for structured logging
- **golang-migrate** for schema migrations

### Local development
- **Docker Compose**

Suggested local stack:
- API service
- worker service
- Temporal
- Temporal UI
- Postgres

## What not to start with

Avoid overcomplicating v1 with:
- Kafka
- RabbitMQ
- Kubernetes-first deployment
- GraphQL
- a heavyweight ORM
- too many microservices

A very reasonable v1 is:
- one API service
- one worker service
- one Postgres database
- one Temporal cluster

## Proposed architecture

## API service
Responsibilities:
- expose REST endpoints
- trigger sync workflows
- return cached data
- return sync status and history

Example endpoints:
- `POST /sync/full`
- `POST /sync/environments/{id}`
- `POST /sync/environments/{id}/resource-types/{type}`
- `GET /environments`
- `GET /resources`
- `GET /resources/{id}`
- `GET /sync-runs/{id}`

## Worker service
Responsibilities:
- execute sync workflows
- call Informatica APIs
- fan out environment tasks
- fan out resource-type tasks
- fetch resource detail payloads
- normalize and upsert records
- record failures and retries

## Database
Suggested core tables:
- `environments`
- `service_accounts`
- `resource_types`
- `resources`
- `resource_snapshots` or raw payload storage
- `sync_runs`
- `sync_tasks`
- `sync_errors`

## Workflow model

A good first Temporal workflow structure:

### Full sync workflow
1. discover environments
2. fan out one environment sync workflow per environment
3. aggregate results

### Environment sync workflow
1. find admin-capable service account
2. fan out one resource-type sync workflow per resource type
3. aggregate results

### Resource type sync workflow
1. resolve credentials
2. list resources of this type
3. fan out detail fetch activities or batched child workflows
4. upsert results
5. return summary

### Resource detail activity
1. fetch full details for one resource
2. normalize payload
3. upsert into database
4. capture raw payload if needed

## Data model guidance

There are really two kinds of data to preserve:

### 1. Normalized queryable metadata
Use this for:
- environments
- identifiers
- names
- resource types
- ownership
- timestamps
- status fields

### 2. Raw API payloads
Use this for:
- full source-of-truth detail snapshots
- troubleshooting
- future schema evolution
- fields you do not yet model explicitly

A good pattern is:
- normalized top-level tables
- plus JSONB payload storage for raw details

## Parallelism strategy

This application should parallelize at multiple levels:
- across environments
- across resource types inside each environment
- across resources inside each resource type

Important guardrails:
- apply concurrency limits
- respect Informatica API rate limits
- centralize retry policy
- avoid unbounded fan-out

Temporal is a strong fit for this.

## Credential model

Do not store raw Informatica admin credentials in pipeline logic or request payloads.

Recommended approach:
- store credential references in Postgres
- resolve secrets through a secret manager or environment-backed config
- fetch admin credentials only when needed for worker tasks

Over time, this can evolve into a more formal credential resolver abstraction.

## Sync modes to support early

Good v1 sync modes:
- full sync across all environments
- sync one environment
- sync one environment and one resource type
- retry failed resource syncs

Defer until later:
- event-driven updates
- change stream ingestion
- advanced diff-only sync logic

## Suggested project structure

```text
/cmd
  /api
  /worker
/internal
  /api
  /config
  /db
  /informatics
  /logging
  /models
  /repository
  /services
  /temporal
    /activities
    /workflows
  /normalize
/migrations
/docs
/deploy
```

## Suggested v1 priorities

1. define the data model
2. define the list of resource types to cache first
3. stand up Postgres + Temporal + API + worker locally
4. implement environment discovery
5. implement admin service-account discovery
6. implement one resource-type sync end to end
7. add status tracking and retry visibility
8. expand resource coverage gradually

## Reasonable first milestone

A good first milestone is complete when the app can:
- discover environments
- identify an admin service account per environment
- sync one resource type end to end
- upsert normalized metadata and raw payloads into Postgres
- expose sync status through the API

## Longer-term enhancements

Later, the system could add:
- incremental refresh heuristics
- diffing between sync runs
- lineage between Informatica objects
- search and filtering APIs
- RBAC and multi-user access
- web UI
- audit and compliance views

## Supporting docs

- [Data model proposal](docs/data-model-proposal.md)
- [Architecture notes](docs/architecture.md)

## Final recommendation

Start simple and make the execution model trustworthy.

The best v1 is not the one with the most resource types, it is the one that proves:
- distributed metadata sync works
- retries are safe
- upserts are correct
- the API is useful
- operators can see what happened when something fails
