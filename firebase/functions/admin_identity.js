// Roles are server-owned (see users rules); never trust a caller payload or
// the editable users.email field. Email compatibility uses verified ID tokens.
function isTrustedAdmin(auth, user = {}) {
  return !!auth && (auth.token?.admin === true ||
    (auth.token?.email === 'proxiplay.pro@gmail.com') ||
    user.user_role === 'admin' || user.userRole === 'admin');
}
module.exports = {isTrustedAdmin};
