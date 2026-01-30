const admin = require('firebase-admin');
const fs = require('fs');

// Load the service account key
const serviceAccount = require('./admin-key.json');

// Initialize Firebase with Admin rights
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

async function listCommercants() {
  let nextPageToken;
  let commercantsCount = 0;
  let output = "";

  output += "--- LISTE DES COMPTES COMMERCANTS ---\n\n";

  try {
    const db = admin.firestore();
    let allCommercants = [];

    // Retrieve users in batches of 1000
    do {
      const listUsersResult = await admin.auth().listUsers(1000, nextPageToken);

      // Check each user
      for (const userRecord of listUsersResult.users) {
        try {
          const docSnap = await db.collection('users').doc(userRecord.uid).get();
          if (docSnap.exists) {
            const data = docSnap.data() || {};
            
            // Filter only commercants
            if (data.user_role === 'commercant') {
              commercantsCount++;
              
              // Format timestamps
              const birthday = data.birthday ? new Date(data.birthday.toDate()).toLocaleDateString('fr-FR') : '-';
              const createdTime = data.created_time ? new Date(data.created_time.toDate()).toLocaleString('fr-FR') : '-';
              const partLastUpdate = data.part_last_update ? new Date(data.part_last_update.toDate()).toLocaleString('fr-FR') : '-';
              
              allCommercants.push({
                uid: userRecord.uid,
                emailVerified: userRecord.emailVerified ? "✅ Vérifié" : "❌ Non vérifié",
                accountStatus: data.account_status || '-',
                email: data.email || userRecord.email || '-',
                firstName: data.first_name || '-',
                lastName: data.last_name || '-',
                pseudo: data.pseudo || '-',
                phoneNumber: data.phone_number || '-',
                city: data.city || '-',
                birthday: birthday,
                createdTime: createdTime,
                partLastUpdate: partLastUpdate,
                remainingPart: data.remaining_part !== undefined ? data.remaining_part : '-'
              });
            }
          }
        } catch (e) {
          // Skip on error
          output += `Erreur lors de la lecture du compte ${userRecord.uid}: ${e.message}\n`;
        }
      }

      nextPageToken = listUsersResult.pageToken;
    } while (nextPageToken);

    // Display results
    if (allCommercants.length === 0) {
      output += "Aucun compte commerçant trouvé.\n";
      fs.writeFileSync('commercants_list.txt', output, 'utf8');
      console.log("Aucun compte commerçant trouvé. Fichier 'commercants_list.txt' créé.");
      return;
    }

    allCommercants.forEach((commercant, index) => {
      output += `\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      output += `COMMERÇANT #${index + 1}\n`;
      output += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      output += `UID                : ${commercant.uid}\n`;
      output += `Statut du compte   : ${commercant.accountStatus}\n`;
      output += `Email vérifié      : ${commercant.emailVerified}\n`;
      output += `─────────────────────────────────────────────────────\n`;
      output += `Nom                : ${commercant.lastName}\n`;
      output += `Prénom             : ${commercant.firstName}\n`;
      output += `Pseudo             : ${commercant.pseudo}\n`;
      output += `Email              : ${commercant.email}\n`;
      output += `Téléphone          : ${commercant.phoneNumber}\n`;
      output += `Ville              : ${commercant.city}\n`;
      output += `Date de naissance  : ${commercant.birthday}\n`;
      output += `─────────────────────────────────────────────────────\n`;
      output += `Compte créé le     : ${commercant.createdTime}\n`;
      output += `Dernière MAJ part  : ${commercant.partLastUpdate}\n`;
      output += `Participations restantes : ${commercant.remainingPart}\n`;
    });

    output += `\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    output += `TOTAL : ${commercantsCount} compte(s) commerçant(s) trouvé(s).\n`;
    output += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n`;

    // Write to file
    fs.writeFileSync('commercants_list.txt', output, 'utf8');
    console.log(`✅ Fichier 'commercants_list.txt' créé avec succès !`);
    console.log(`📊 ${commercantsCount} compte(s) commerçant(s) exporté(s).`);

  } catch (error) {
    output += `\nErreur : ${error}\n`;
    fs.writeFileSync('commercants_list.txt', output, 'utf8');
    console.log('❌ Erreur :', error);
    console.log('Fichier partiel créé : commercants_list.txt');
  }
}

listCommercants();
