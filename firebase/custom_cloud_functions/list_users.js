const admin = require('firebase-admin');
const fs = require('fs');

// On charge la clé que vous venez de télécharger et renommer
const serviceAccount = require('./admin-key.json');

// Initialisation de Firebase avec les droits Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

async function listAllUsers(showUid = false) {
  let nextPageToken;
  let count = 0;
  let shopKeepersCount = 0;
  let playersCount = 0;
  let adminCount = 0;
  let output = "";

  output += "--- LISTE DES UTILISATEURS ---\n";
  let header = "STATUT | EMAIL                          ";
  let separator = "-------";
  
  if (showUid) {
    header += " | UID                             ";
    separator += "+-----------------------------------";
  }
  
  header += " | USER_ROLE     | FIRST_NAME         | LAST_NAME          | PSEUDO";
  separator += "+---------------+--------------------+--------------------+--------";
  
  output += header + "\n";
  output += separator + "\n";

  try {
    // On récupère les utilisateurs par lot de 1000
    do {
      const listUsersResult = await admin.auth().listUsers(1000, nextPageToken);
      const db = admin.firestore();

      // Utiliser une boucle for...of pour pouvoir await les accès Firestore
      for (const userRecord of listUsersResult.users) {
        count++;
        const statusIcon = userRecord.emailVerified ? "✅" : "❌";
        const email = userRecord.email || "Sans Email (Anonyme/Tél)";

        let firstName = "-";
        let lastName = "-";
        let pseudo = "-";
        let userRole = "-";

        try {
          const docSnap = await db.collection('users').doc(userRecord.uid).get();
          if (docSnap.exists) {
            const data = docSnap.data() || {};
            firstName = data.first_name || firstName;
            lastName = data.last_name || lastName;
            pseudo = data.pseudo || pseudo;
            userRole = data.user_role || userRole;
            
            // Count shop keepers and players
            if (userRole === 'commercant') {
              shopKeepersCount++;
            } else if (userRole === 'joueur') {
              playersCount++;
            } else if (userRole === 'admin') {
              adminCount++;
            }
          }
        } catch (e) {
          // En cas d'erreur de lecture Firestore, on garde les valeurs par défaut
        }

        let logLine = `${statusIcon}     | ${email.padEnd(30)}`;
        if (showUid) {
          logLine += ` | ${String(userRecord.uid).padEnd(30)}`;
        }
        logLine += ` | ${String(userRole).padEnd(13)} | ${String(firstName).padEnd(18)} | ${String(lastName).padEnd(18)} | ${String(pseudo).padEnd(6)}`;
        
        output += logLine + "\n";
      }

      nextPageToken = listUsersResult.pageToken;
    } while (nextPageToken);

    output += separator + "\n";
    output += `TOTAL : ${count} comptes trouvés.\n`;
    output += `  - Shop Keepers : ${shopKeepersCount}\n`;
    output += `  - Players : ${playersCount}\n`;
    output += `  - Admin : ${adminCount}\n`;

    // Write to file
    fs.writeFileSync('users_list.txt', output, 'utf8');
    console.log(`✅ Fichier 'users_list.txt' créé avec succès !`);
    console.log(`\n📊 STATISTIQUES :`);
    console.log(`  - TOTAL : ${count} comptes trouvés`);
    console.log(`  - Commerçants : ${shopKeepersCount}`);
    console.log(`  - Joueurs : ${playersCount}`);
    console.log(`  - Admin : ${adminCount}`);

  } catch (error) {
    output += `\nErreur : ${error}\n`;
    fs.writeFileSync('users_list.txt', output, 'utf8');
    console.log('❌ Erreur :', error);
    console.log('Fichier partiel créé : users_list.txt');
  }
}

// Récupère le paramètre de la ligne de commande pour afficher l'UID (--uid)
const showUid = process.argv.includes('--uid');
listAllUsers(showUid);