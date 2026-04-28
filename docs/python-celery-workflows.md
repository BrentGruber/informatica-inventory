# Python and Celery Workflow Proposal

## Goal

This document describes how the Informatica metadata cache system could be implemented using **Python + Celery** instead of **Go + Temporal**.

The goal is not to replace the main recommendation automatically. The goal is to make the tradeoff concrete by showing what the workflow model would look like in a Celery-based design.

## High-level architecture

A Python + Celery version would likely use:
- **FastAPI** or **Flask** for the REST API
- **Celery** for distributed background jobs
- **Redis** or **RabbitMQ** as the Celery broker
- **Postgres** for the metadata cache
- **SQLAlchemy Core** or raw SQL for persistence

Recommended Python stack if taking this route:
- `fastapi`
- `celery`
- `redis` or `rabbitmq`
- `psycopg` or `asyncpg`
- `sqlalchemy` core only, or plain SQL
- `alembic` for migrations
- `pydantic` for request/response and configuration models

## Core workflow shape

The requested workflow is naturally hierarchical.

1. discover all environments
2. for each environment, find an admin service account
3. for each resource type, trigger a task
4. for each listed resource, fetch full details
5. upsert each resource into Postgres

This maps reasonably well to Celery using:
- root tasks
- groups
- chords
- chained follow-up tasks

## Suggested workflow decomposition

## 1. Full sync entrypoint
A single API request or scheduler trigger starts the full sync.

Responsibilities:
- create a `sync_run` record
- enqueue an environment discovery task
- return a sync run id immediately

## 2. Environment discovery task
Responsibilities:
- call Informatica to list environments
- upsert environments
- fan out one environment sync task per environment

## 3. Environment sync task
Responsibilities:
- find an admin-capable service account for the environment
- upsert that service account
- fan out one resource-type sync task per enabled type

## 4. Resource type sync task
Responsibilities:
- resolve admin credentials
- list all resources of that type in the environment
- upsert summary-level records if desired
- fan out detail fetch tasks for each resource

## 5. Resource detail task
Responsibilities:
- fetch full resource detail
- normalize payload
- upsert resource row
- extract and upsert relationships

## 6. Aggregation / completion tasks
Responsibilities:
- mark resource-type sync complete
- mark environment sync complete
- mark full sync complete
- record final stats and failures

## Celery building blocks

### `group`
Use for parallel fan-out.

Examples:
- run one task per environment
- run one task per resource type
- run one task per resource detail fetch

### `chord`
Use when you need to run many tasks in parallel and then execute a completion callback.

Examples:
- fan out all environment syncs, then mark the parent sync run complete
- fan out all resource detail pulls, then summarize the results

### `chain`
Use for linear sequencing when one step directly follows another.

Examples:
- resolve service account -> list resources -> fan out detail tasks

## Example data flow

### Full sync
```text
POST /sync/full
  -> create sync_run
  -> enqueue discover_environments(sync_run_id)
```

### Environment discovery
```text
discover_environments(sync_run_id)
  -> list environments from Informatica
  -> upsert environments
  -> group(sync_environment.s(sync_run_id, environment_id) for each environment)
  -> chord(...)(finalize_full_sync.s(sync_run_id))
```

### Environment sync
```text
sync_environment(sync_run_id, environment_id)
  -> find admin service account
  -> upsert service account
  -> group(sync_resource_type.s(sync_run_id, environment_id, resource_type_code) for each enabled type)
  -> chord(...)(finalize_environment_sync.s(sync_run_id, environment_id))
```

### Resource type sync
```text
sync_resource_type(sync_run_id, environment_id, resource_type_code)
  -> resolve credentials
  -> list resources for type
  -> group(sync_resource_detail.s(sync_run_id, environment_id, resource_type_code, external_id) for each resource)
  -> chord(...)(finalize_resource_type_sync.s(sync_run_id, environment_id, resource_type_code))
```

## Example pseudocode

## Celery app setup

```python
from celery import Celery

celery_app = Celery(
    "informatica_inventory",
    broker="redis://redis:6379/0",
    backend="redis://redis:6379/1",
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    task_track_started=True,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
)
```

## Full sync API endpoint

```python
from fastapi import APIRouter
from app.db import create_sync_run
from app.tasks import discover_environments

router = APIRouter()

@router.post("/sync/full")
def start_full_sync() -> dict:
    sync_run_id = create_sync_run(run_type="full_sync", status="queued")
    task = discover_environments.delay(sync_run_id)
    return {
        "sync_run_id": sync_run_id,
        "task_id": task.id,
        "status": "queued",
    }
```

## Discover environments task

```python
from celery import chord
from app.celery_app import celery_app
from app.db import upsert_environment, mark_sync_run_failed
from app.informatica import list_environments
from app.tasks.environments import sync_environment, finalize_full_sync

@celery_app.task(bind=True, autoretry_for=(Exception,), retry_backoff=True, max_retries=5)
def discover_environments(self, sync_run_id: int):
    try:
        environments = list_environments()
        environment_ids = []

        for env in environments:
            environment_id = upsert_environment(env)
            environment_ids.append(environment_id)

        header = [sync_environment.s(sync_run_id, environment_id) for environment_id in environment_ids]
        return chord(header)(finalize_full_sync.s(sync_run_id))
    except Exception as exc:
        mark_sync_run_failed(sync_run_id, str(exc))
        raise
```

## Sync one environment

```python
from celery import chord
from app.celery_app import celery_app
from app.db import upsert_service_account, get_enabled_resource_types
from app.informatica import find_admin_service_account
from app.tasks.resources import sync_resource_type, finalize_environment_sync

@celery_app.task(bind=True, autoretry_for=(Exception,), retry_backoff=True, max_retries=5)
def sync_environment(self, sync_run_id: int, environment_id: int):
    service_account = find_admin_service_account(environment_id)
    service_account_id = upsert_service_account(environment_id, service_account)

    resource_types = get_enabled_resource_types()
    header = [
        sync_resource_type.s(sync_run_id, environment_id, service_account_id, resource_type.code)
        for resource_type in resource_types
    ]
    return chord(header)(finalize_environment_sync.s(sync_run_id, environment_id))
```

## Sync one resource type

```python
from celery import chord
from app.celery_app import celery_app
from app.db import create_sync_task, mark_sync_task_failed
from app.informatica import list_resources_for_type, resolve_credentials
from app.tasks.resources import sync_resource_detail, finalize_resource_type_sync

@celery_app.task(bind=True, autoretry_for=(Exception,), retry_backoff=True, max_retries=5)
def sync_resource_type(self, sync_run_id: int, environment_id: int, service_account_id: int, resource_type_code: str):
    sync_task_id = create_sync_task(
        sync_run_id=sync_run_id,
        environment_id=environment_id,
        resource_type_code=resource_type_code,
        status="running",
    )

    try:
        credentials = resolve_credentials(service_account_id)
        resources = list_resources_for_type(environment_id, resource_type_code, credentials)

        header = [
            sync_resource_detail.s(sync_run_id, environment_id, resource_type_code, service_account_id, resource)
            for resource in resources
        ]
        return chord(header)(finalize_resource_type_sync.s(sync_run_id, sync_task_id, environment_id, resource_type_code))
    except Exception as exc:
        mark_sync_task_failed(sync_task_id, str(exc))
        raise
```

## Resource detail sync

```python
from app.celery_app import celery_app
from app.db import upsert_resource, upsert_relationships
from app.informatica import get_resource_detail, resolve_credentials
from app.normalize import normalize_resource, extract_relationships

@celery_app.task(bind=True, autoretry_for=(Exception,), retry_backoff=True, max_retries=5)
def sync_resource_detail(
    self,
    sync_run_id: int,
    environment_id: int,
    resource_type_code: str,
    service_account_id: int,
    resource_summary: dict,
):
    credentials = resolve_credentials(service_account_id)
    detail = get_resource_detail(environment_id, resource_type_code, resource_summary["id"], credentials)

    normalized = normalize_resource(environment_id, resource_type_code, resource_summary, detail)
    resource_id = upsert_resource(normalized)

    relationships = extract_relationships(environment_id, resource_id, detail)
    upsert_relationships(relationships)

    return {
        "resource_id": resource_id,
        "resource_type_code": resource_type_code,
    }
```

## Finalizer tasks

```python
@celery_app.task
def finalize_resource_type_sync(results, sync_run_id: int, sync_task_id: int, environment_id: int, resource_type_code: str):
    # summarize counts, mark sync task completed
    return {
        "environment_id": environment_id,
        "resource_type_code": resource_type_code,
        "resource_count": len(results),
    }

@celery_app.task
def finalize_environment_sync(results, sync_run_id: int, environment_id: int):
    # summarize environment-level results
    return {
        "environment_id": environment_id,
        "resource_type_runs": len(results),
    }

@celery_app.task
def finalize_full_sync(results, sync_run_id: int):
    # summarize and mark sync_run complete
    return {
        "sync_run_id": sync_run_id,
        "environment_runs": len(results),
    }
```

## Recommended Celery task boundaries

Use Celery tasks for:
- environment discovery
- environment sync
- resource-type sync
- resource detail sync
- finalization

Do not make every tiny DB call its own task.

That would create too much task overhead.

## Operational concerns in a Celery design

## 1. Idempotency
Every task should be safe to retry.

Examples:
- environment upserts must be idempotent
- resource upserts must be idempotent
- relationship upserts must be idempotent
- completion tasks should tolerate duplicate invocation safely

## 2. Rate limiting
If Informatica rate limits aggressively, Celery workers need explicit protections.

Options:
- per-task rate limits
- queue separation by resource type
- concurrency limits per environment
- backoff and retry

## 3. Large fan-out control
A big environment with many resources can create task explosions.

Mitigations:
- batch detail tasks
- chunk resource ids into groups
- use per-resource-type concurrency caps

## 4. Sync state persistence
Do not rely on Celery result backend alone for operational visibility.

Use Postgres tables such as:
- `sync_runs`
- `sync_tasks`
- `sync_errors`

Those should remain the primary operational record.

## 5. Credential resolution
Do not serialize raw admin credentials into Celery payloads.

Pass:
- environment id
- service account id
- credential reference

Then resolve secrets inside the worker at execution time.

## 6. Error handling
Celery retries are useful, but structured failure recording is still needed.

Every failure path should:
- update `sync_tasks`
- optionally insert into `sync_errors`
- preserve context such as environment, resource type, and resource id

## Advantages of Python + Celery here

- quick API integration development
- large Python ecosystem
- easy experimentation and payload inspection
- many teams move fast in Python for this style of glue system

## Drawbacks compared to Go + Temporal

- workflow coordination is less explicit and less ergonomic than Temporal
- fan-out/fan-in orchestration is possible, but easier to make messy
- retries and resumability are more manual conceptually
- deployment and environment management are often more annoying
- long-term operational discipline usually requires more care

## When Python + Celery is a good choice

This stack is a good fit if:
- initial development is highly exploratory
- Informatica API work is still being discovered
- the team moves much faster in Python
- early value comes from iterating on metadata extraction logic quickly

## When Go + Temporal is still stronger

Go + Temporal remains a stronger fit if the project is expected to become:
- a long-running production service
- highly parallel and operationally important
- strict about workflow visibility and reliability
- control-plane oriented from the start

## Recommendation

If choosing Python, I would structure it as:
- FastAPI for API layer
- Celery for distributed workers
- Postgres for sync state and metadata cache
- Redis or RabbitMQ as broker
- raw SQL or SQLAlchemy Core for persistence

If choosing this route, keep the architecture disciplined:
- persistent sync state in Postgres
- idempotent upserts everywhere
- credentials resolved at worker runtime
- explicit completion/finalizer tasks
- bounded fan-out to avoid runaway task volume

That gives you a workable Python version without losing the core system shape you want.
