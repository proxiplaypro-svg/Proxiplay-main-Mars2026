# Share Promo Backend

## Firestore structure

Implemented document paths:

- `app_config/share_promo`
- `referrals/{referralId}`
- `users/{uid}/private/share_state`
- `reward_events/{eventId}`
- `admin_stats/share_promo`

Normalized from the request:

- `users/{uid}/private/share_state/current` is not a valid Firestore document path.
- `admin_stats/share_promo/current` is not a valid Firestore document path.

The backend uses the closest deployable equivalents above.

## Cloud Functions

- `getSharePromoState`
- `createReferral`
- `registerReferralAcceptance`
- `grantReferralReward`
- `expireOldReferrals`
- `adminUpsertSharePromo`
- `adminGetSharePromoStats`

Source files:

- `firebase/functions/src/share_promo/types.ts`
- `firebase/functions/src/share_promo/firestore.ts`
- `firebase/functions/src/share_promo/index.ts`

## Required indexes

- `referrals`: `inviterUid ASC, createdAt DESC`
- `referrals`: `status ASC, createdAt DESC`
- `referrals`: `inviteCode ASC`
- `reward_events`: `uid ASC, createdAt DESC`

## Deployment notes

1. Run `npm install` in `firebase/functions`.
2. Run `npm run compile` in `firebase/functions`.
3. Deploy functions, Firestore rules and indexes.
4. Set the custom claim `admin: true` on admin users.
5. Optionally define `SHARE_PROMO_APP_URL` for generated invitation links.

## Reward note

The backend grants play-based rewards by incrementing `users/{uid}.remaining_part`.
For any future reward type that targets another wallet or entitlement store, extend
`applyRewardToUser()` in `firebase/functions/src/share_promo/firestore.ts`.
