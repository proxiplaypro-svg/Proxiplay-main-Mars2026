// Roles are server-owned (see users rules); never trust a caller payload or
// the editable users.email field. Email compatibility uses verified ID tokens.
// Etape A (0.8) : l'e-mail historique ne compte que s'il est verifie.
// Etape B, apres pose du custom claim admin : supprimer la ligne e-mail.
function isTrustedAdmin(auth, user = {}) {
  return !!auth && (auth.token?.admin === true ||
    (auth.token?.email === 'proxiplay.pro@gmail.com' && auth.token?.email_verified === true) ||
    user.user_role === 'admin' || user.userRole === 'admin');
}
module.exports = {isTrustedAdmin};
