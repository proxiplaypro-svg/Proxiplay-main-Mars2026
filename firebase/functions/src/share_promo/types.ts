import * as admin from 'firebase-admin';

export type ReferralStatus =
  | 'pending'
  | 'accepted'
  | 'expired'
  | 'cancelled'
  | 'rejected';

export type RewardStatus =
  | 'not_earned'
  | 'available'
  | 'granted'
  | 'blocked';

export interface SharePromoConfig {
  enabled: boolean;
  kind: string;
  title: string;
  message: string;
  ctaText: string;
  startAt: admin.firestore.Timestamp | null;
  endAt: admin.firestore.Timestamp | null;
  rewardType: string;
  rewardValue: number;
  maxRewardsPerUser: number;
  maxRewardsPerInvitee: number;
  requireInviteeSignup: boolean;
  audience: string;
  isDraft: boolean;
  priority: number;
  updatedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  updatedBy: string;
}

export interface ReferralRecord {
  campaignId: string;
  inviterUid: string;
  inviterPseudo: string | null;
  inviteeUid: string | null;
  inviteeContact: string | null;
  inviteCode: string;
  shareChannel: string;
  status: ReferralStatus;
  rewardStatus: RewardStatus;
  rewardType: string;
  rewardValue: number;
  createdAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  acceptedAt: admin.firestore.Timestamp | null;
  rewardGrantedAt: admin.firestore.Timestamp | null;
  expiredAt: admin.firestore.Timestamp | null;
  createdFromDeviceId: string | null;
  acceptedFromDeviceId: string | null;
  metadata: Record<string, unknown>;
}

export interface ShareStateRecord {
  pendingCount: number;
  acceptedCount: number;
  grantedCount: number;
  rewardAvailable: boolean;
  lastReferralAt: admin.firestore.Timestamp | null;
  lastRewardAt: admin.firestore.Timestamp | null;
  remainingEligibleRewards: number;
  currentBannerKind: string | null;
  currentBannerTitle: string | null;
  currentBannerMessage: string | null;
  updatedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
}

export interface RewardEventRecord {
  uid: string;
  referralId: string;
  campaignId: string;
  type: string;
  value: number;
  status: string;
  createdAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  grantedBy: string;
}

export interface AdminStatsRecord {
  pendingReferrals: number;
  acceptedReferrals: number;
  grantedRewards: number;
  activeCampaigns: number;
  updatedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
}

export interface GetSharePromoStateResponse {
  showBanner: boolean;
  kind: string | null;
  title: string | null;
  message: string | null;
  ctaText: string | null;
  action: string | null;
  campaign: {
    id: string;
    rewardType: string;
    rewardValue: number;
  } | null;
}

export interface CreateReferralInput {
  shareChannel?: string;
  inviteeContact?: string | null;
  createdFromDeviceId?: string | null;
  metadata?: Record<string, unknown>;
}

export interface CreateReferralResponse {
  referralId: string;
  inviteCode: string;
  shareMessage: string;
  shareLink: string;
}

export interface RegisterReferralAcceptanceInput {
  inviteCode?: string;
  acceptedFromDeviceId?: string | null;
}

export interface AdminUpsertSharePromoInput {
  enabled?: boolean;
  kind?: string;
  title?: string;
  message?: string;
  ctaText?: string;
  startAt?: string | number | admin.firestore.Timestamp | null;
  endAt?: string | number | admin.firestore.Timestamp | null;
  rewardType?: string;
  rewardValue?: number;
  maxRewardsPerUser?: number;
  maxRewardsPerInvitee?: number;
  requireInviteeSignup?: boolean;
  audience?: string;
  isDraft?: boolean;
  priority?: number;
}
