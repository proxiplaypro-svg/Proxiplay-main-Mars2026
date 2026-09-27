// Politique unique pour les deux canaux marchand ("nouveau gagnant") de
// notifyPrizeWon : email et push partagent le meme critere, donc une seule
// fonction plutot qu'un helper limite a l'email. N'affecte jamais les
// canaux joueur, ni les ecritures prize/my_lots/claim_code/stats.
function shouldNotifyMerchantForPrize(enseigneData, prize = {}) {
  // La remise est un contrat du lot. Une enseigne administree peut encore
  // avoir un vrai commercant et lui confier explicitement la remise.
  if (prize.fulfillment_type === "merchant") return true;
  if (["partner", "platform"].includes(prize.fulfillment_type)) return false;
  // Compatibilite des lots historiques, qui ne portaient pas ce contrat.
  return !(enseigneData && enseigneData.managed_by_admin === true);
}
function merchantNotificationSkipReason(enseigneData, prize = {}) {
  if (prize.fulfillment_type === 'partner') return 'partner_delivery';
  if (prize.fulfillment_type === 'platform') return 'platform_delivery';
  return enseigneData && enseigneData.managed_by_admin === true ? 'managed_by_admin_legacy' : '';
}
module.exports = {shouldNotifyMerchantForPrize, merchantNotificationSkipReason};
