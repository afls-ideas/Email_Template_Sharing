# LSC Email Template Sharing by Public Group

Share Life Sciences Cloud (LSC) email templates with users via **Public Groups** instead of (or in addition to) territory-based sharing.

## Problem

Out of the box, LSC only supports sharing email templates by assigning them to **territories** (via Admin Console > Email > Email Templates). Sharing rules are an alternative, but Salesforce limits the number of sharing rules per object. This solution uses a trigger-based approach that scales without hitting sharing rule limits.

## Solution Overview

A custom field (`ShareWithGroupName__c`) on `LifeSciEmailTemplate` holds a **Public Group name** (user-friendly, no need to look up IDs). An Apex trigger resolves the name to a Group ID at runtime and automatically creates/manages `LifeSciEmailTemplateShare` and `LifeSciEmailTmplFragmentShare` records.

### Data Model

```
LifeSciEmailTemplate (OWD: Private)
  ├── ShareWithGroupName__c       -- custom Text(255) field holding a Public Group name
  ├── LifeSciEmailTemplateShare   -- share object (RowCause = 'Manual', AccessLevel = 'Read')
  │
  ├── LifeSciEmailTmplRelaFrgmt   -- junction (ControlledByParent, auto-inherits access)
  │     └── LifeSciEmailTmplFragment (OWD: Private)
  │           └── LifeSciEmailTmplFragmentShare  -- share object (RowCause = 'Manual')
  │
  └── LifeSciEmailTmplSnapshot    -- child (ControlledByParent, auto-inherits access)
```

**Objects that need explicit sharing (OWD = Private):**
| Object | Share Object | Managed by trigger? |
|--------|-------------|-------------------|
| `LifeSciEmailTemplate` | `LifeSciEmailTemplateShare` | Yes |
| `LifeSciEmailTmplFragment` | `LifeSciEmailTmplFragmentShare` | Yes |

**Objects that inherit access automatically (ControlledByParent):**
| Object | Parent |
|--------|--------|
| `LifeSciEmailTmplRelaFrgmt` | `LifeSciEmailTemplate` |
| `LifeSciEmailTmplSnapshot` | `LifeSciEmailTemplate` |

### Components

| Component | Type | Description |
|-----------|------|-------------|
| `ShareWithGroupName__c` | Custom Field | Text(255) on `LifeSciEmailTemplate` — holds Public Group name |
| `DEMO_EmailTmplGroupSharing` | Apex Trigger | Fires before/after insert, update, delete |
| `DEMO_EmailTmplGroupSharingHandler` | Apex Class | Handler with group name lookup and sharing logic |
| `DEMO_EmailTmplGroupSharingTest` | Apex Test | 7 test methods, 97%+ coverage |

## How It Works

| Event | Behavior |
|-------|----------|
| **Insert** with group name populated | Resolves name to Group ID, creates template share + fragment shares |
| **Update** group name changed | Removes old shares, resolves new name, creates new shares |
| **Update** group name cleared | Removes all Manual shares |
| **Delete** template | Fragment shares cleaned up (template shares cascade-delete) |
| **Invalid group name** | Silently skipped (no shares created, no error) |

The trigger uses `before delete` to cache fragment IDs before the junction records (`LifeSciEmailTmplRelaFrgmt`) cascade-delete, then cleans up fragment shares in `after delete`.

Group name resolution queries `Group WHERE Name = :name AND Type = 'Regular'`, so only Public Groups are matched (not roles, territories, or queues).

## Setup

### Prerequisites

- LSC org with API version 65.0+ (objects like `LifeSciEmailTemplate` require this)
- Field Email module enabled

### Deploy

```bash
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

### Configure

1. **Create a Public Group** (Setup > Users > Public Groups) with the users who should receive template access.

2. **Set the group name on a template** — either via:
   - Direct field edit on the `LifeSciEmailTemplate` record (e.g., type `All Field Reps`)
   - Data Loader / Workbench for bulk updates
   - A custom UI (e.g., screen flow or LWC)

   The group name must match exactly (case-sensitive).

3. **Verify** — query the share records:
   ```sql
   SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
   FROM LifeSciEmailTemplateShare
   WHERE RowCause = 'Manual'
   ```

### Run Tests

```bash
sf apex test run --class-names DEMO_EmailTmplGroupSharingTest --target-org <your-org-alias> --synchronous --code-coverage
```

## Coexistence with Territory Sharing

This trigger creates shares with `RowCause = 'Manual'`. LSC's built-in territory sharing uses `RowCause = 'LSC4CEAutoShare'`. Both can coexist — Salesforce grants the most permissive access level when multiple share records exist for the same user.

## Limitations

- **Single group per template** — the field holds one group name. To share with multiple groups, extend the solution to use a related list or multi-value field.
- **Group name must be exact** — if the Public Group is renamed, the field value must be updated to match. Consider a validation rule or flow to verify the name exists.
- **Fragment share cleanup on delete** — removes all Manual-cause fragment shares for affected fragments. If the same fragment is shared via multiple templates to different groups, clearing one template's group may remove shares needed by another. For production use, consider reference-counting fragment shares.
