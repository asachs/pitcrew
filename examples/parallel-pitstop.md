# Example: Two-Mechanic Pit Stop

Adding a barcode field to both a backend schema and a frontend form, in parallel.

## Option A: One Command (pitstop-auto)

```bash
export MINIMAX_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."

./tools/pitstop-auto.sh ~/src/myproject \
  "Add a barcode/EAN field to the product schema in src/schema.clj and the product form in src/pages/Dashboard.tsx"
```

The crew chief (Sonnet) decomposes the task into 2 beads, dispatches mechanics in parallel, and merges. ~20s total, ~$0.01.

## Option B: Manual Beads

```bash
export MINIMAX_API_KEY="sk-..."
cd ~/src/myproject

bd create \
  --title "Add barcode field to product schema" \
  --body "Edit src/schema.clj. Find (def product-schema. Add after :product/supplier:
   {:db/ident       :product/barcode
    :db/valueType   :db.type/string
    :db/cardinality :db.cardinality/one
    :db/doc         \"Barcode or EAN number\"}
Only add this one attribute." \
  --label "file:src/schema.clj"

bd create \
  --title "Add barcode field to product form" \
  --body "Edit src/pages/Dashboard.tsx. Find the add-product form. Add an Input for barcode between supplier and submit. Label: Barcode / EAN. Placeholder: 5901234123457. Add barcode to form state and API POST body." \
  --label "file:src/pages/Dashboard.tsx"

# Get the bead IDs
bd list --status open

# Dispatch both mechanics in parallel
./tools/pitstop.sh ~/src/myproject <bead-id-1> <bead-id-2>
```

## Results

```
PIT STOP COMPLETE

Mechanics:   2 dispatched, 2 merged, 0 failed, 0 escalated
Time:        6s total
Tokens:      0.8k sent, 0.5k received
Est. cost:   $0.001
```

## With Context Files

If the mechanic editing Dashboard.tsx needs to understand the schema types:

```bash
bd create \
  --title "Add barcode field to product form" \
  --body "Add barcode input to the product form." \
  --label "file:src/pages/Dashboard.tsx" \
  --label "file:src/schema.clj"
```

The first `file:` label is the write target. The second is injected as read-only context — the mechanic can see the schema but won't modify it.

## Lessons

1. **Constrain the brief** — without "do NOT change naming conventions", the model renamed hyphens to underscores
2. **Two bays, zero conflicts** — different files = always green flag
3. **Context files help** — when the mechanic needs to understand types from another file, add it as a second `file:` label
