// Politique unique pour les deux canaux marchand ("nouveau gagnant") de
// notifyPrizeWon : email et push partagent le meme critere, donc une seule
// fonction plutot qu'un helper limite a l'email. N'affecte jamais les
// canaux joueur, ni les ecritures prize/my_lots/claim_code/stats.
function shouldNotifyMerchantForPrize(enseigneData) {
  return !(enseigneData && enseigneData.managed_by_admin === true);
}
module.exports = {shouldNotifyMerchantForPrize};
