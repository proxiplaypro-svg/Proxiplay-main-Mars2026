## Firebase Functions Source Of Truth

- `firebase/functions` is the deployed source of truth for Cloud Functions.
- `firebase/custom_cloud_functions` is a mirror or legacy copy kept for compatibility and inspection.
- Do not deploy from `firebase/custom_cloud_functions`.
- Functional changes must be made first in `firebase/functions`.
- If a mirrored file is kept in `firebase/custom_cloud_functions`, keep it intentionally synchronized with the deployed version.

Recommended targeted deploy command, without running it here:

```bash
firebase deploy --only functions:participateInGameTransaction
```
