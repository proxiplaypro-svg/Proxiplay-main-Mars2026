const admin = require('firebase-admin');
const serviceAccount = require('./admin-key.json');

// Initialisation
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

// On récupère l'email que vous écrivez dans la console
// process.argv[2] veut dire "le 3ème mot tapé dans la commande"
const emailTarget = process.argv[2];

async function forceValidate() {
  if (!emailTarget) {
    console.log("⚠️  Erreur : Vous avez oublié de mettre l'email !");
    console.log("Usage : node validate_email.js bob@exemple.com");
    return;
  }

  console.log(`🔍 Recherche de l'utilisateur : ${emailTarget}...`);

  try {
    // 1. Trouver l'utilisateur
    const user = await admin.auth().getUserByEmail(emailTarget);
    
    // 2. Le mettre à jour
    await admin.auth().updateUser(user.uid, {
      emailVerified: true
    });

    console.log(`✅ SUCCÈS ! L'email de ${emailTarget} est maintenant validé.`);
    console.log("L'utilisateur peut se connecter immédiatement.");

  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      console.log("❌ Erreur : Aucun utilisateur trouvé avec cet email.");
    } else {
      console.log('❌ Erreur technique :', error.message);
    }
  }
}

forceValidate();