---
name: and-then-cancel
description: Cancel the and-then task queue and allow normal session exit
allowed_tools:
  - Bash
---

# Cancel And-Then Queue

Remove the task queue and allow normal session behavior.

---

```bash
if [[ -f ".claude/and-then-queue.local.md" ]]; then
    rm ".claude/and-then-queue.local.md"
    echo "✅ And-then queue cancelled"
else
    echo "ℹ️  No active and-then queue"
fi
```
