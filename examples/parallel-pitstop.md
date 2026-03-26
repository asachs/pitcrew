# Example: Two-Mechanic Pit Stop

Adding a barcode field to both a backend schema and a frontend form, in parallel.

## Make the Pit Calls

```bash
cd ~/pitlane

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
```

## Box Box — Dispatch

```bash
export MINIMAX_API_KEY="sk-..."

./tools/mechanic.sh beads-abc ~/src/myproject &
./tools/mechanic.sh beads-def ~/src/myproject &
wait
```

## Results

**Mechanic 1** (schema): Added `:product/barcode`. 15k tokens in, 13k out.
**Mechanic 2** (frontend): Added Input, form state, API body. 9.5k in, 8k out.

~30 seconds. ~$0.004 total.

## Release

```bash
./tools/release.sh beads-abc ~/src/myproject  # Green flag
./tools/release.sh beads-def ~/src/myproject  # Green flag
```

## Lessons

1. **Constrain the brief** — without "do NOT change naming conventions", the model renamed hyphens to underscores
2. **Two bays, zero conflicts** — different files = always green flag
3. **Model prefix matters** — Aider needs `openai/MiniMax-M2.5` with custom API base
